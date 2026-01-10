import SwiftUI
import UniformTypeIdentifiers

struct GeneralPreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager
    @State private var showingImporter = false
    @State private var maxAttemptsInput = ""
    @State private var delayInput = ""
    @State private var maxAttemptsValid = true
    @State private var delayValid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("SSH") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("SSH binary")
                        HStack(spacing: 8) {
                            TextField("SSH binary", text: $manager.sshBinaryPath)
                                .font(.system(.body, design: .monospaced))
                                .frame(minWidth: 320, maxWidth: .infinity)
                                .layoutPriority(1)
                            Button("Choose...") {
                                showingImporter = true
                            }
                            .frame(minWidth: 90)
                            Button("Reset") {
                                manager.resetSSHBinaryPath()
                            }
                            .frame(minWidth: 80)
                        }
                        ValidationBadge(
                            title: sshPathBadgeTitle,
                            systemImage: sshPathBadgeImage,
                            color: sshPathBadgeColor
                        )
                    }
                    GridRow {
                        Text("Status")
                        Text(sshPathStatus)
                            .foregroundStyle(sshPathStatusColor)
                        Color.clear
                            .frame(width: 1, height: 1)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox("Auto-Reconnect") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Reconnect after unexpected disconnects")
                        Spacer()
                        Toggle("", isOn: $manager.autoReconnectEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Text("Max attempts")
                            TextField("", text: $maxAttemptsInput)
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: maxAttemptsInput) { _, newValue in
                                    validateMaxAttempts(newValue)
                                }
                            Text(maxAttemptsValid ? "0 = unlimited" : "Invalid")
                                .foregroundColor(maxAttemptsValid ? .secondary : .red)
                        }
                        HStack(spacing: 8) {
                            Text("Delay")
                            TextField("", text: $delayInput)
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: delayInput) { _, newValue in
                                    validateDelay(newValue)
                                }
                            Text(delayValid ? "seconds" : "Invalid")
                                .foregroundColor(delayValid ? .secondary : .red)
                        }
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox("Paths") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Config file")
                        Text(configPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(width: 1, height: 1)
                    }
                    GridRow {
                        Text("Control sockets")
                        Text(manager.controlSocketBasePath)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(width: 1, height: 1)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            maxAttemptsInput = "\(manager.autoReconnectMaxAttempts)"
            delayInput = "\(Int(manager.autoReconnectDelaySeconds))"
        }
        .onChange(of: manager.autoReconnectMaxAttempts) { _, newValue in
            if maxAttemptsValid {
                maxAttemptsInput = "\(newValue)"
            }
        }
        .onChange(of: manager.autoReconnectDelaySeconds) { _, newValue in
            if delayValid {
                delayInput = "\(Int(newValue))"
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    manager.sshBinaryPath = url.path
                }
            case .failure:
                manager.lastError = "Failed to select SSH binary."
            }
        }
    }

    private var configPath: String {
        let base = applicationSupportPath
        return base.appending("/config.json")
    }

    private var applicationSupportPath: String {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "~/Library/Application Support/Tunnels"
        }
        return url.appendingPathComponent("Tunnels", isDirectory: true).path
    }

    private var sshPathStatus: String {
        let path = manager.sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return "Using default /usr/bin/ssh"
        }
        if FileManager.default.isExecutableFile(atPath: path) {
            return "Executable found"
        }
        if FileManager.default.fileExists(atPath: path) {
            return "File exists but is not executable"
        }
        return "Path does not exist"
    }

    private var sshPathStatusColor: Color {
        let path = manager.sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return .secondary
        }
        return FileManager.default.isExecutableFile(atPath: path) ? .secondary : .red
    }

    private var sshPathBadgeTitle: String {
        let path = manager.sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || FileManager.default.isExecutableFile(atPath: path) {
            return "Valid"
        }
        return "Invalid"
    }

    private var sshPathBadgeImage: String {
        let path = manager.sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || FileManager.default.isExecutableFile(atPath: path) {
            return "checkmark.seal.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var sshPathBadgeColor: Color {
        let path = manager.sshBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || FileManager.default.isExecutableFile(atPath: path) {
            return .green
        }
        return .red
    }

    private func validateMaxAttempts(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value >= 0 else {
            maxAttemptsValid = false
            return
        }
        maxAttemptsValid = true
        manager.autoReconnectMaxAttempts = value
    }

    private func validateDelay(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= 1 else {
            delayValid = false
            return
        }
        delayValid = true
        manager.autoReconnectDelaySeconds = value
    }
}
