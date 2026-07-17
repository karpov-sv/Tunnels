import SwiftUI

struct HostsPreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager
    @State private var selection: UUID?
    @State private var showingAddHost = false
    @State private var showingRemoveHostConfirmation = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(manager.hostProfiles, selection: $selection) { host in
                    HStack(spacing: 6) {
                        StatusDotView(state: hostIndicatorState(host))
                        Text(host.alias)
                    }
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity)

                Divider()

                HStack(spacing: 8) {
                    Button("Add Host", systemImage: "plus", action: addHostPlaceholder)
                        .labelStyle(.iconOnly)
                    Button("Remove Host", systemImage: "minus") {
                        showingRemoveHostConfirmation = true
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selection == nil)
                    .confirmationDialog(
                        "Remove this host and all its tunnels?",
                        isPresented: $showingRemoveHostConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Remove", role: .destructive) {
                            if let selection {
                                let id = selection
                                Task {
                                    if await manager.removeHost(id: id) {
                                        self.selection = nil
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            if let selection,
               let host = manager.hostProfile(id: selection) {
                HostDetailPane(hostId: host.id)
            } else {
                VStack {
                    Text("Select a host to edit")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selection == nil {
                selection = manager.hostProfiles.first?.id
            }
        }
        .onChange(of: manager.hostProfiles) { _, newValue in
            if let selection, !newValue.contains(where: { $0.id == selection }) {
                self.selection = newValue.first?.id
            } else if selection == nil {
                selection = newValue.first?.id
            }
        }
    }

    private func addHostPlaceholder() {
        let existing = Set(manager.hostProfiles.map { $0.alias })
        var index = manager.hostProfiles.count + 1
        var alias = "new-host-\(index)"
        while existing.contains(alias) {
            index += 1
            alias = "new-host-\(index)"
        }
        manager.addHost(alias: alias)
        selection = manager.hostProfiles.last?.id
    }

    private func hostIndicatorState(_ host: HostProfile) -> TunnelIndicatorState {
        if manager.isHostReconnecting(host) {
            return .reconnecting
        }
        return manager.runtimeStateSnapshot(for: host).isMasterRunning ? .connected : .disconnected
    }
}

private struct HostDetailPane: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.openWindow) private var openWindow
    let hostId: UUID

    @State private var aliasDraft = ""
    @State private var respectsConfigForwardings = false
    @State private var showingAddTunnel = false
    @State private var editingTunnel: TunnelEditContext?
    @State private var selectedTunnelId: UUID?
    @State private var showingRemoveTunnelConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(host.alias)
                .font(.title2)
                .bold()

            GroupBox("Host") {
                LabeledContent("Alias") {
                    HStack(spacing: 8) {
                        TextField("Alias", text: $aliasDraft)
                            .frame(minWidth: 240)
                        Button("Save") {
                            Task {
                                await manager.updateHostAlias(hostId: hostId, alias: aliasDraft)
                            }
                        }
                        .disabled(aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(connectionTitle) {
                            Task {
                                if shouldDisconnectHost {
                                    await manager.disconnectHost(id: hostId)
                                } else {
                                    await manager.connectHost(id: hostId)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        Button("Details...") {
                            openWindow(id: "host-details", value: hostId)
                        }
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Respect SSH config forwardings", isOn: $respectsConfigForwardings)
                        .toggleStyle(.switch)
                    Text("Use LocalForward/RemoteForward/DynamicForward from ~/.ssh/config for this host.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }

            GroupBox("Tunnels") {
                VStack(alignment: .leading, spacing: 12) {
                    if host.tunnels.isEmpty {
                        Text("No tunnels configured")
                            .foregroundStyle(.secondary)
                    } else {
                        Table(host.tunnels, selection: $selectedTunnelId) {
                            TableColumn("Status") { tunnel in
                                TunnelStatusCell(state: tunnelIndicatorState(for: tunnel, host: host, manager: manager))
                            }
                            .width(min: 110, ideal: 140)
                            TableColumn("Tunnel") { tunnel in
                                Text(tunnel.displaySummary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .width(min: 220, ideal: 280)
                            TableColumn("Type") { tunnel in
                                Text(tunnel.type.displayName)
                            }
                            .width(min: 80, ideal: 100)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }

                    HStack {
                        Button("Add Tunnel...") {
                            showingAddTunnel = true
                        }
                        Button(startStopTitle) {
                            if let tunnel = selectedTunnel {
                                manager.toggleTunnel(hostId: hostId, tunnelId: tunnel.id)
                            }
                        }
                        .disabled(selectedTunnel == nil || selectedTunnelIsBusy)
                        Button("Duplicate") {
                            if let tunnel = selectedTunnel {
                                manager.duplicateTunnel(hostId: hostId, tunnelId: tunnel.id)
                            }
                        }
                        .disabled(selectedTunnel == nil || selectedTunnelIsBusy)
                        Button("Edit...") {
                            if let tunnel = selectedTunnel {
                                editingTunnel = TunnelEditContext(hostId: hostId, tunnel: tunnel)
                            }
                        }
                        .disabled(selectedTunnel == nil || selectedTunnelIsBusy)
                        Button("Remove") {
                            showingRemoveTunnelConfirmation = true
                        }
                        .disabled(selectedTunnel == nil || selectedTunnelIsBusy)
                        .confirmationDialog(
                            "Remove this tunnel?",
                            isPresented: $showingRemoveTunnelConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) {
                                if let tunnel = selectedTunnel {
                                    let tunnelId = tunnel.id
                                    selectedTunnelId = nil
                                    Task {
                                        await manager.removeTunnel(hostId: hostId, tunnelId: tunnelId)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            resetDrafts()
        }
        .onChange(of: hostId) { _, _ in
            resetDrafts()
        }
        .onChange(of: host.alias) { _, newValue in
            aliasDraft = newValue
        }
        .onChange(of: respectsConfigForwardings) { _, newValue in
            guard newValue != host.respectsConfigForwardings else { return }
            Task {
                await manager.updateHostForwardings(hostId: hostId, respectsConfigForwardings: newValue)
            }
        }
        .onChange(of: host.respectsConfigForwardings) { _, newValue in
            respectsConfigForwardings = newValue
        }
        .onChange(of: host.tunnels) { _, newValue in
            if selectedTunnelId == nil {
                selectedTunnelId = newValue.first?.id
            }
        }
        .sheet(isPresented: $showingAddTunnel) {
            TunnelEditorView(hostId: hostId, tunnel: nil)
                .environmentObject(manager)
        }
        .sheet(item: $editingTunnel) { context in
            TunnelEditorView(hostId: context.hostId, tunnel: context.tunnel)
                .environmentObject(manager)
        }
    }

    private var host: HostProfile {
        manager.hostProfile(id: hostId) ?? HostProfile(alias: "Unknown")
    }

    private var selectedTunnel: TunnelSpec? {
        guard let selectedTunnelId else { return nil }
        return host.tunnels.first { $0.id == selectedTunnelId }
    }

    private func resetDrafts() {
        aliasDraft = host.alias
        respectsConfigForwardings = host.respectsConfigForwardings
        selectedTunnelId = host.tunnels.first?.id
    }

    private var selectedTunnelIsBusy: Bool {
        guard let selectedTunnel else { return false }
        return manager.isTunnelOperationInProgress(selectedTunnel.id)
    }

    private var startStopTitle: String {
        guard let selectedTunnel else { return "Start" }
        let shouldStop = manager.shouldStopTunnel(hostId: hostId, tunnelId: selectedTunnel.id)
        return shouldStop ? "Stop" : "Start"
    }

    private var shouldDisconnectHost: Bool {
        manager.shouldDisconnectHost(host)
    }

    private var connectionTitle: String {
        shouldDisconnectHost ? "Disconnect Host" : "Connect Host"
    }

}

private struct TunnelEditContext: Identifiable {
    let id = UUID()
    let hostId: UUID
    let tunnel: TunnelSpec
}
