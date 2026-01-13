import AppKit
import CoreServices
import Darwin
import Foundation
import Security
import UserNotifications

struct HostRuntimeState: Equatable {
    let controlSocketPath: String
    var isMasterRunning: Bool
}

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var hostProfiles: [HostProfile] = []
    @Published private(set) var runtimeStates: [UUID: HostRuntimeState] = [:]
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var tunnelErrors: Set<UUID> = []
    @Published var preferencesTab: PreferencesTab = .general
    @Published private(set) var reconnectingHosts: Set<UUID> = []
    @Published private(set) var reconnectingTunnelsByHost: [UUID: Set<UUID>] = [:]
    @Published var logNotificationsEnabled: Bool {
        didSet {
            persistLogNotificationsEnabled()
            if logNotificationsEnabled {
                configureNotificationsIfNeeded()
            } else {
                clearNotificationQueue()
            }
        }
    }
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var codeSigningStatus: CodeSigningStatus = .unknown
    @Published var autoReconnectEnabled: Bool {
        didSet {
            persistAutoReconnect()
        }
    }
    @Published var autoReconnectMaxAttempts: Int {
        didSet {
            persistAutoReconnectMaxAttempts()
        }
    }
    @Published var autoReconnectDelaySeconds: Double {
        didSet {
            persistAutoReconnectDelaySeconds()
        }
    }
    @Published var sshBinaryPath: String {
        didSet {
            persistSSHBinaryPath()
        }
    }
    @Published var lastError: String?

    private let sshPathKey = "sshBinaryPath"
    private let autoReconnectKey = "autoReconnectEnabled"
    private let autoReconnectMaxAttemptsKey = "autoReconnectMaxAttempts"
    private let autoReconnectDelayKey = "autoReconnectDelaySeconds"
    private let logNotificationsEnabledKey = "logNotificationsEnabled"
    private let defaultSSHPath = "/usr/bin/ssh"
    private let defaultReconnectMaxAttempts = 5
    private let defaultReconnectDelaySeconds: Double = 6
    private let controlSocketManager = ControlSocketManager()
    private let configInspector = ConfigInspector()
    private let fileManager: FileManager
    private let configURL: URL
    private var statusTask: Task<Void, Never>?
    private let isRunningInAppBundle: Bool
    private lazy var notificationCenter: UNUserNotificationCenter? = {
        guard isRunningInAppBundle else { return nil }
        return UNUserNotificationCenter.current()
    }()
    private let notificationDelegate = NotificationDelegate()
    private var pendingNotificationEntries: [LogEntry] = []
    private var notificationFlushTask: Task<Void, Never>?
    private var lastNotificationIdentifier: String?
    private var lastNotificationDate: Date?
    private let notificationCoalesceDelaySeconds: Double = 2
    private let notificationIdentifierReuseWindowSeconds: Double = 4

    init(fileManager: FileManager = .default) {
        let bundleURL = Bundle.main.bundleURL
        let isBundled = bundleURL.pathExtension == "app" || Bundle.main.bundleIdentifier != nil
        self.isRunningInAppBundle = isBundled
        let storedPath = UserDefaults.standard.string(forKey: sshPathKey)
        self.sshBinaryPath = storedPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? storedPath ?? defaultSSHPath
            : defaultSSHPath
        if UserDefaults.standard.object(forKey: autoReconnectKey) != nil {
            self.autoReconnectEnabled = UserDefaults.standard.bool(forKey: autoReconnectKey)
        } else {
            self.autoReconnectEnabled = false
        }
        if UserDefaults.standard.object(forKey: autoReconnectMaxAttemptsKey) != nil {
            self.autoReconnectMaxAttempts = UserDefaults.standard.integer(forKey: autoReconnectMaxAttemptsKey)
        } else {
            self.autoReconnectMaxAttempts = defaultReconnectMaxAttempts
        }
        if UserDefaults.standard.object(forKey: autoReconnectDelayKey) != nil {
            self.autoReconnectDelaySeconds = UserDefaults.standard.double(forKey: autoReconnectDelayKey)
        } else {
            self.autoReconnectDelaySeconds = defaultReconnectDelaySeconds
        }
        if UserDefaults.standard.object(forKey: logNotificationsEnabledKey) != nil {
            self.logNotificationsEnabled = UserDefaults.standard.bool(forKey: logNotificationsEnabledKey)
        } else {
            self.logNotificationsEnabled = false
        }
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let tunnelsDir = appSupport?.appendingPathComponent("Tunnels", isDirectory: true)
        self.configURL = tunnelsDir?.appendingPathComponent("config.json") ?? URL(fileURLWithPath: "config.json")

        if let tunnelsDir {
            do {
                try fileManager.createDirectory(at: tunnelsDir, withIntermediateDirectories: true)
            } catch {
                logError("Failed to create config directory: \(error)")
            }
        }

        load()
        refreshCodeSigningStatus()
        statusTask = Task { [weak self] in
            await self?.pollStatusLoop()
        }
        configureNotificationsIfNeeded()
    }

    deinit {
        statusTask?.cancel()
        notificationFlushTask?.cancel()
    }

    func hostProfile(id: UUID) -> HostProfile? {
        hostProfiles.first { $0.id == id }
    }

    func runtimeStateSnapshot(for host: HostProfile) -> HostRuntimeState {
        if let state = runtimeStates[host.id] {
            return state
        }
        let socketPath = controlSocketManager.socketPath(for: host.alias)
        return HostRuntimeState(controlSocketPath: socketPath, isMasterRunning: false)
    }

    private func ensureRuntimeState(for host: HostProfile) -> HostRuntimeState {
        if let state = runtimeStates[host.id] {
            return state
        }
        let socketPath = controlSocketManager.socketPath(for: host.alias)
        let state = HostRuntimeState(controlSocketPath: socketPath, isMasterRunning: false)
        runtimeStates[host.id] = state
        return state
    }

    func statusLabel(for host: HostProfile) -> String {
        let state = runtimeStateSnapshot(for: host)
        if state.isMasterRunning {
            return "Connected"
        }
        return "Disconnected"
    }

    func addHost(alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hostProfiles.append(HostProfile(alias: trimmed))
        persist()
        logInfo("Added host \(trimmed)")
    }

    func updateHostAlias(hostId: UUID, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let host = hostProfile(id: hostId), host.alias != trimmed else { return }
        Task {
            await disconnectHost(host: host)
        }
        updateHost(hostId: hostId) { host in
            host.alias = trimmed
            host.tunnels = host.tunnels.map { tunnel in
                var updated = tunnel
                updated.isActive = false
                return updated
            }
        }
        runtimeStates[hostId] = nil
        logInfo("Updated host alias to \(trimmed)")
    }

    func updateHostForwardings(hostId: UUID, respectsConfigForwardings: Bool) {
        guard let host = hostProfile(id: hostId) else { return }
        updateHost(hostId: hostId) { host in
            host.respectsConfigForwardings = respectsConfigForwardings
        }
        if runtimeStates[hostId]?.isMasterRunning == true {
            Task {
                await disconnectHost(host: host)
            }
        }
        logInfo("Updated config forwardings for \(host.alias): \(respectsConfigForwardings ? "enabled" : "disabled")")
    }

    func removeHost(id: UUID) {
        guard let host = hostProfile(id: id) else { return }
        Task {
            await disconnectHost(host: host)
        }
        hostProfiles.removeAll { $0.id == id }
        runtimeStates[id] = nil
        tunnelErrors.subtract(host.tunnels.map(\.id))
        reconnectingHosts.remove(id)
        reconnectingTunnelsByHost[id] = nil
        persist()
        logInfo("Removed host \(host.alias)")
    }

    func addTunnel(hostId: UUID, spec: TunnelSpec) {
        updateHost(hostId: hostId) { host in
            host.tunnels.append(spec)
        }
        clearTunnelError(spec.id)
        if let host = hostProfile(id: hostId) {
            logInfo("Added tunnel \(spec.displaySummary) for \(host.alias)")
        }
    }

    func updateTunnel(hostId: UUID, tunnelId: UUID, updated: TunnelSpec) {
        guard let host = hostProfile(id: hostId),
              let existing = host.tunnels.first(where: { $0.id == tunnelId }) else { return }
        if existing.isActive {
            Task {
                await stopTunnel(host: host, tunnel: existing)
            }
        }
        updateHost(hostId: hostId) { host in
            guard let index = host.tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
            host.tunnels[index].type = updated.type
            host.tunnels[index].localPort = updated.localPort
            host.tunnels[index].remoteHost = updated.remoteHost
            host.tunnels[index].remotePort = updated.remotePort
            host.tunnels[index].isActive = false
        }
        clearTunnelError(tunnelId)
        logInfo("Updated tunnel \(existing.displaySummary) for \(host.alias)")
    }

    func duplicateTunnel(hostId: UUID, tunnelId: UUID) {
        guard let host = hostProfile(id: hostId),
              let existingIndex = host.tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let existing = host.tunnels[existingIndex]
        let duplicate = TunnelSpec(
            id: UUID(),
            type: existing.type,
            localPort: existing.localPort,
            remoteHost: existing.remoteHost,
            remotePort: existing.remotePort,
            isActive: false
        )
        updateHost(hostId: hostId) { host in
            host.tunnels.insert(duplicate, at: existingIndex + 1)
        }
        clearTunnelError(duplicate.id)
        logInfo("Duplicated tunnel \(existing.displaySummary) for \(host.alias)")
    }

    func removeTunnel(hostId: UUID, tunnelId: UUID) {
        guard let host = hostProfile(id: hostId),
              let tunnel = host.tunnels.first(where: { $0.id == tunnelId }) else { return }
        Task {
            if tunnel.isActive {
                await stopTunnel(host: host, tunnel: tunnel)
            }
        }
        updateHost(hostId: hostId) { host in
            host.tunnels.removeAll { $0.id == tunnelId }
        }
        clearTunnelError(tunnelId)
        logInfo("Removed tunnel \(tunnel.displaySummary) for \(host.alias)")
    }

    func toggleTunnel(hostId: UUID, tunnelId: UUID) {
        guard let host = hostProfile(id: hostId),
              let tunnel = host.tunnels.first(where: { $0.id == tunnelId }) else { return }
        Task {
            if tunnel.isActive {
                await stopTunnel(host: host, tunnel: tunnel)
            } else {
                await startTunnel(host: host, tunnel: tunnel)
            }
        }
    }

    func disconnectHost(id: UUID) async {
        guard let host = hostProfile(id: id) else { return }
        await disconnectHost(host: host)
    }

    func shutdownAll() async {
        for host in hostProfiles {
            await disconnectHost(id: host.id)
        }
    }

    func connectHost(id: UUID) async {
        guard let host = hostProfile(id: id) else { return }
        _ = await ensureMaster(for: host)
    }

    func isHostReconnecting(_ host: HostProfile) -> Bool {
        reconnectingHosts.contains(host.id)
    }

    func isTunnelReconnecting(hostId: UUID, tunnelId: UUID) -> Bool {
        reconnectingTunnelsByHost[hostId]?.contains(tunnelId) == true
    }

    var notificationsAvailable: Bool {
        isRunningInAppBundle
    }

    func configureNotificationsIfNeeded() {
        guard isRunningInAppBundle else { return }
        registerAppWithLaunchServices()
        notificationCenter?.delegate = notificationDelegate
        refreshNotificationAuthorizationStatus()
        if logNotificationsEnabled {
            Task {
                await requestNotificationAuthorizationIfNeeded()
            }
        }
    }

    func refreshCodeSigningStatus() {
        let bundleURL = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            codeSigningStatus = .unsigned
            return
        }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard infoStatus == errSecSuccess, let info = info as? [String: Any] else {
            codeSigningStatus = .unsigned
            return
        }
        let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
        if teamIdentifier?.isEmpty != false {
            codeSigningStatus = .adHoc
        } else {
            codeSigningStatus = .signed
        }
    }

    func requestNotificationAuthorization() {
        guard notificationsAvailable else { return }
        registerAppWithLaunchServices()
        notificationCenter?.delegate = notificationDelegate
        Task {
            await requestNotificationAuthorizationIfNeeded()
        }
    }

    func refreshNotificationAuthorizationStatus() {
        guard notificationsAvailable else {
            notificationAuthorizationStatus = .notDetermined
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let notificationCenter = self.notificationCenter else { return }
            let settings = await notificationCenter.notificationSettings()
            self.notificationAuthorizationStatus = settings.authorizationStatus
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func resetSSHBinaryPath() {
        sshBinaryPath = defaultSSHPath
        logInfo("Reset SSH binary to \(defaultSSHPath)")
    }

    func startAllTunnels(hostId: UUID) async {
        guard let host = hostProfile(id: hostId) else { return }
        logInfo("Starting all tunnels for \(host.alias)")
        for tunnel in host.tunnels where !tunnel.isActive {
            await startTunnel(host: host, tunnel: tunnel)
        }
    }

    func stopAllTunnels(hostId: UUID) async {
        guard let host = hostProfile(id: hostId) else { return }
        logInfo("Stopping all tunnels for \(host.alias)")
        for tunnel in host.tunnels where tunnel.isActive {
            await stopTunnel(host: host, tunnel: tunnel)
        }
    }

    func localPortInUse(_ port: Int) -> Bool {
        !isLocalPortAvailable(port)
    }

    func inspectConfig(for hostId: UUID) async -> ExecResult? {
        guard let host = hostProfile(id: hostId) else { return nil }
        return await configInspector.inspect(alias: host.alias, sshPath: resolvedSSHPath)
    }

    var controlSocketBasePath: String {
        controlSocketManager.basePath
    }

    private func startTunnel(host: HostProfile, tunnel: TunnelSpec) async {
        guard await ensureMaster(for: host) else { return }
        logInfo("Starting tunnel \(tunnel.displaySummary) for \(host.alias)")
        if tunnel.type != .remote {
            let port = tunnel.localPort
            if !isLocalPortAvailable(port) {
                let state = ensureRuntimeState(for: host)
                let cancelArgs = ["-S", state.controlSocketPath, "-O", "cancel"]
                    + tunnelArguments(for: tunnel)
                    + [host.alias]
                _ = await runSSH(args: cancelArgs)
            }

            if !isLocalPortAvailable(port) {
                logInfo("Local port \(port) is already in use. Skipping forward.")
                return
            }
        }
        let state = ensureRuntimeState(for: host)
        let args = ["-S", state.controlSocketPath, "-O", "forward"]
            + tunnelArguments(for: tunnel)
            + [host.alias]
        let result = await runSSH(args: args)
        if result.success {
            setTunnelActive(hostId: host.id, tunnelId: tunnel.id, active: true)
            clearTunnelError(tunnel.id)
            logInfo("Started tunnel \(tunnel.displaySummary) for \(host.alias)")
        } else {
            if tunnel.type != .remote && !isLocalPortAvailable(tunnel.localPort) {
                setTunnelActive(hostId: host.id, tunnelId: tunnel.id, active: true)
                clearTunnelError(tunnel.id)
                logInfo("Tunnel \(tunnel.displaySummary) appears active despite ssh error; port \(tunnel.localPort) is in use.")
            } else {
                logError(failureMessage(action: "Start tunnel \(tunnel.displaySummary)", result: result))
                markTunnelError(tunnel.id)
            }
        }
    }

    private func stopTunnel(host: HostProfile, tunnel: TunnelSpec) async {
        logInfo("Stopping tunnel \(tunnel.displaySummary) for \(host.alias)")
        let state = ensureRuntimeState(for: host)
        let args = ["-S", state.controlSocketPath, "-O", "cancel"]
            + tunnelArguments(for: tunnel)
            + [host.alias]
        let result = await runSSH(args: args)
        if result.success {
            setTunnelActive(hostId: host.id, tunnelId: tunnel.id, active: false)
            clearTunnelError(tunnel.id)
            logInfo("Stopped tunnel \(tunnel.displaySummary) for \(host.alias)")
        } else {
            logError(failureMessage(action: "Stop tunnel \(tunnel.displaySummary)", result: result))
            markTunnelError(tunnel.id)
        }
        if !hasActiveTunnels(hostId: host.id) {
            await disconnectHost(id: host.id)
        }
    }

    private func ensureMaster(for host: HostProfile) async -> Bool {
        let state = ensureRuntimeState(for: host)
        let check = await runSSH(args: ["-S", state.controlSocketPath, "-O", "check", host.alias])
        if check.success {
            runtimeStates[host.id]?.isMasterRunning = true
            return true
        }

        logInfo("Starting master connection for \(host.alias)")
        var args = [
            "-MNf",
            "-o",
            "ControlMaster=yes",
            "-o",
            "ControlPersist=600"
        ]
        if !host.respectsConfigForwardings {
            args += ["-o", "ClearAllForwardings=yes"]
        }
        args += [
            "-o",
            "ControlPath=\(escapeForSSHOptionValue(state.controlSocketPath))",
            "-o",
            "ExitOnForwardFailure=yes",
            host.alias
        ]
        let result = await runSSH(args: args)
        runtimeStates[host.id]?.isMasterRunning = result.success
        if !result.success {
            logError(failureMessage(action: "Start master connection for \(host.alias)", result: result))
        } else {
            logInfo("Master connection established for \(host.alias)")
        }
        return result.success
    }

    private func tunnelArguments(for tunnel: TunnelSpec) -> [String] {
        switch tunnel.type {
        case .dynamic:
            return ["-D", "\(tunnel.localPort)"]
        case .local:
            let host = tunnel.remoteHost ?? ""
            let port = tunnel.remotePort.map(String.init) ?? ""
            return ["-L", "\(tunnel.localPort):\(host):\(port)"]
        case .remote:
            let host = tunnel.remoteHost ?? ""
            let remotePort = tunnel.remotePort.map(String.init) ?? ""
            return ["-R", "\(remotePort):\(host):\(tunnel.localPort)"]
        }
    }

    private func hasActiveTunnels(hostId: UUID) -> Bool {
        hostProfiles.first(where: { $0.id == hostId })?.tunnels.contains(where: { $0.isActive }) ?? false
    }

    private func setTunnelActive(hostId: UUID, tunnelId: UUID, active: Bool) {
        updateHost(hostId: hostId) { host in
            guard let index = host.tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
            host.tunnels[index].isActive = active
        }
    }

    private func updateHost(hostId: UUID, mutation: (inout HostProfile) -> Void) {
        guard let index = hostProfiles.firstIndex(where: { $0.id == hostId }) else { return }
        mutation(&hostProfiles[index])
        persist()
    }

    private func runSSH(args: [String]) async -> ExecResult {
        let path = resolvedSSHPath
        return await Task.detached {
            SSHProcessRunner.run(executablePath: path, args: args)
        }.value
    }

    private func disconnectHost(host: HostProfile) async {
        let socketPath = controlSocketManager.socketPath(for: host.alias)
        logInfo("Disconnecting host \(host.alias)")
        let result = await runSSH(args: ["-S", socketPath, "-O", "exit", host.alias])
        if !result.success {
            logError(failureMessage(action: "Disconnect host \(host.alias)", result: result))
        } else {
            logInfo("Disconnected host \(host.alias)")
        }
        updateHost(hostId: host.id) { host in
            host.tunnels = host.tunnels.map { tunnel in
                var updated = tunnel
                updated.isActive = false
                return updated
            }
        }
        tunnelErrors.subtract(host.tunnels.map(\.id))
        reconnectingHosts.remove(host.id)
        reconnectingTunnelsByHost[host.id] = nil
        runtimeStates[host.id]?.isMasterRunning = false
    }

    private func pollStatusLoop() async {
        while !Task.isCancelled {
            await refreshStatus()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func refreshStatus() async {
        for host in hostProfiles {
            let state = ensureRuntimeState(for: host)
            let wasRunning = state.isMasterRunning
            let result = await runSSH(args: ["-S", state.controlSocketPath, "-O", "check", host.alias])
            let isRunning = result.success
            runtimeStates[host.id]?.isMasterRunning = isRunning
            if wasRunning && !isRunning {
                let activeTunnels = host.tunnels.filter { $0.isActive }
                let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "SSH master for \(host.alias) disconnected unexpectedly."
                    : "SSH master for \(host.alias) disconnected unexpectedly: \(detail)"
                logError(message)
                updateHost(hostId: host.id) { host in
                    host.tunnels = host.tunnels.map { tunnel in
                        var updated = tunnel
                        updated.isActive = false
                        return updated
                    }
                }
                if autoReconnectEnabled {
                    Task {
                        await attemptAutoReconnect(hostId: host.id, previouslyActive: activeTunnels)
                    }
                }
            }
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: configURL.path) else {
            hostProfiles = []
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            hostProfiles = try JSONDecoder().decode([HostProfile].self, from: data)
        } catch {
            logError("Failed to load config: \(error)")
            hostProfiles = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(hostProfiles)
            try data.write(to: configURL, options: [.atomic])
        } catch {
            logError("Failed to save config: \(error)")
        }
    }

    private func logInfo(_ message: String) {
        appendLog(LogEntry(level: .info, message: message))
    }

    private func logError(_ message: String) {
        lastError = message
        appendLog(LogEntry(level: .error, message: message))
    }

    private func appendLog(_ entry: LogEntry) {
        logs.append(entry)
        enqueueNotificationIfNeeded(entry)
    }

    private func enqueueNotificationIfNeeded(_ entry: LogEntry) {
        guard logNotificationsEnabled, isRunningInAppBundle else { return }
        pendingNotificationEntries.append(entry)
        if notificationFlushTask == nil {
            notificationFlushTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.notificationCoalesceDelaySeconds))
                self.flushLogNotifications()
            }
        }
    }

    private func flushLogNotifications() {
        notificationFlushTask = nil
        guard logNotificationsEnabled else {
            pendingNotificationEntries.removeAll()
            return
        }
        guard let notificationCenter else {
            pendingNotificationEntries.removeAll()
            return
        }
        let entries = pendingNotificationEntries
        pendingNotificationEntries.removeAll()
        guard !entries.isEmpty else { return }

        let now = Date()
        let identifier: String
        if let lastDate = lastNotificationDate,
           let lastIdentifier = lastNotificationIdentifier,
           now.timeIntervalSince(lastDate) <= notificationIdentifierReuseWindowSeconds {
            identifier = lastIdentifier
        } else {
            identifier = UUID().uuidString
        }
        lastNotificationDate = now
        lastNotificationIdentifier = identifier

        let content = UNMutableNotificationContent()
        content.title = "Tunnels"
        if entries.count == 1, let entry = entries.first {
            content.subtitle = entry.level == .error ? "Error" : "Info"
            content.body = entry.message
        } else {
            content.subtitle = "\(entries.count) new log messages"
            content.body = notificationBody(for: entries)
        }
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        notificationCenter.add(request)
    }

    private func notificationBody(for entries: [LogEntry]) -> String {
        let maxLines = 3
        let prefixLines = entries.suffix(maxLines).map { entry in
            let level = entry.level == .error ? "ERROR" : "INFO"
            return "\(level): \(entry.message)"
        }
        let remaining = max(entries.count - maxLines, 0)
        if remaining == 0 {
            return prefixLines.joined(separator: "\n")
        }
        return prefixLines.joined(separator: "\n") + "\n... and \(remaining) more"
    }

    private func clearNotificationQueue() {
        pendingNotificationEntries.removeAll()
        notificationFlushTask?.cancel()
        notificationFlushTask = nil
        lastNotificationIdentifier = nil
        lastNotificationDate = nil
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        guard let notificationCenter else { return }
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            notificationAuthorizationStatus = settings.authorizationStatus
            return
        }
        if !NSApplication.shared.isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        let updatedSettings = await notificationCenter.notificationSettings()
        notificationAuthorizationStatus = updatedSettings.authorizationStatus
    }

    private func registerAppWithLaunchServices() {
        let bundleURL = Bundle.main.bundleURL as CFURL
        LSRegisterURL(bundleURL, true)
    }

    private func failureMessage(action: String, result: ExecResult) -> String {
        if result.combinedOutput.isEmpty {
            return "\(action) failed with exit code \(result.exitCode)"
        }
        return "\(action) failed: \(result.combinedOutput)"
    }

    private func escapeForSSHOptionValue(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character == " " || character == "\\" {
                result.append("\\")
            }
            result.append(character)
        }
    }

    private var resolvedSSHPath: String {
        let trimmed = sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSSHPath : trimmed
    }

    private func persistSSHBinaryPath() {
        UserDefaults.standard.set(sshBinaryPath, forKey: sshPathKey)
    }

    private func persistAutoReconnect() {
        UserDefaults.standard.set(autoReconnectEnabled, forKey: autoReconnectKey)
    }

    private func persistAutoReconnectMaxAttempts() {
        UserDefaults.standard.set(autoReconnectMaxAttempts, forKey: autoReconnectMaxAttemptsKey)
    }

    private func persistAutoReconnectDelaySeconds() {
        UserDefaults.standard.set(autoReconnectDelaySeconds, forKey: autoReconnectDelayKey)
    }

    private func persistLogNotificationsEnabled() {
        UserDefaults.standard.set(logNotificationsEnabled, forKey: logNotificationsEnabledKey)
    }

    private func attemptAutoReconnect(hostId: UUID, previouslyActive: [TunnelSpec]) async {
        guard autoReconnectEnabled else { return }
        guard reconnectingHosts.contains(hostId) == false else { return }
        reconnectingHosts.insert(hostId)
        reconnectingTunnelsByHost[hostId] = Set(previouslyActive.map(\.id))
        defer {
            reconnectingHosts.remove(hostId)
            reconnectingTunnelsByHost[hostId] = nil
        }

        let maxAttempts = autoReconnectMaxAttempts
        let delaySeconds = max(1, autoReconnectDelaySeconds)
        let isUnlimited = maxAttempts == 0

        var attempt = 0
        while true {
            attempt += 1
            guard autoReconnectEnabled else { return }
            guard let host = hostProfile(id: hostId) else { return }
            if runtimeStates[hostId]?.isMasterRunning == true {
                return
            }
            let attemptLabel = isUnlimited ? "\(attempt)" : "\(attempt) of \(maxAttempts)"
            logInfo("Auto-reconnect attempt \(attemptLabel) for \(host.alias)")
            let connected = await ensureMaster(for: host)
            if connected {
                logInfo("Auto-reconnect succeeded for \(host.alias)")
                for tunnel in previouslyActive {
                    if let current = hostProfile(id: hostId)?.tunnels.first(where: { $0.id == tunnel.id }) {
                        await startTunnel(host: host, tunnel: current)
                    }
                }
                return
            }
            if !isUnlimited && attempt >= maxAttempts {
                break
            }
            try? await Task.sleep(for: .seconds(delaySeconds))
        }

        if let host = hostProfile(id: hostId) {
            let tail = isUnlimited ? "after \(attempt) attempts" : "after \(maxAttempts) attempts"
            logInfo("Auto-reconnect failed \(tail) for \(host.alias)")
        }
    }

    func tunnelHasError(_ tunnelId: UUID) -> Bool {
        tunnelErrors.contains(tunnelId)
    }

    private func markTunnelError(_ tunnelId: UUID) {
        tunnelErrors.insert(tunnelId)
    }

    private func clearTunnelError(_ tunnelId: UUID) {
        tunnelErrors.remove(tunnelId)
    }

    func isLocalPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return true }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddress in
                bind(socketFD, sockAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

enum CodeSigningStatus {
    case unknown
    case unsigned
    case adHoc
    case signed
}
