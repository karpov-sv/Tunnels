import SwiftUI

struct HostsPreferencesView: View {
    @EnvironmentObject private var manager: TunnelManager
    @State private var selection: UUID?
    @State private var showingAddHost = false

    var body: some View {
        NavigationSplitView {
            List(manager.hostProfiles, selection: $selection) { host in
                HStack(spacing: 6) {
                    StatusDotView(state: hostIndicatorState(host))
                    Text(host.alias)
                }
            }
            .navigationTitle("Hosts")
            .frame(minWidth: 220)
            .toolbar {
                Button {
                    addHostPlaceholder()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    if let selection {
                        manager.removeHost(id: selection)
                        self.selection = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
            }
        } detail: {
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
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selection == nil {
                selection = manager.hostProfiles.first?.id
            }
        }
        .onChange(of: manager.hostProfiles) { _, newValue in
            if selection == nil {
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
        return manager.runtimeState(for: host).isMasterRunning ? .connected : .disconnected
    }
}

private struct HostDetailPane: View {
    @EnvironmentObject private var manager: TunnelManager
    let hostId: UUID

    @State private var aliasDraft = ""
    @State private var showingAddTunnel = false
    @State private var editingTunnel: TunnelEditContext?
    @State private var selectedTunnelId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Host") {
                LabeledContent("Alias") {
                    HStack(spacing: 8) {
                        TextField("Alias", text: $aliasDraft)
                            .frame(minWidth: 240)
                        Button("Save") {
                            manager.updateHostAlias(hostId: hostId, alias: aliasDraft)
                        }
                        .disabled(aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(connectionTitle) {
                            Task {
                                if isHostConnected {
                                    await manager.disconnectHost(id: hostId)
                                } else {
                                    await manager.connectHost(id: hostId)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Respect SSH config forwardings")
                        Text("Use LocalForward/RemoteForward/DynamicForward from ~/.ssh/config for this host.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { host.respectsConfigForwardings },
                        set: { manager.updateHostForwardings(hostId: hostId, respectsConfigForwardings: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
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
                                TunnelStatusCell(state: tunnelIndicatorState(for: tunnel, manager: manager))
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
                        .disabled(selectedTunnel == nil)
                        Button("Duplicate") {
                            if let tunnel = selectedTunnel {
                                manager.duplicateTunnel(hostId: hostId, tunnelId: tunnel.id)
                            }
                        }
                        .disabled(selectedTunnel == nil)
                        Button("Edit...") {
                            if let tunnel = selectedTunnel {
                                editingTunnel = TunnelEditContext(hostId: hostId, tunnel: tunnel)
                            }
                        }
                        .disabled(selectedTunnel == nil)
                        Button("Remove") {
                            if let tunnel = selectedTunnel {
                                manager.removeTunnel(hostId: hostId, tunnelId: tunnel.id)
                                selectedTunnelId = nil
                            }
                        }
                        .disabled(selectedTunnel == nil)
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(host.alias)
        .onAppear {
            aliasDraft = host.alias
            if selectedTunnelId == nil {
                selectedTunnelId = host.tunnels.first?.id
            }
        }
        .onChange(of: host.alias) { _, newValue in
            aliasDraft = newValue
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

    private var startStopTitle: String {
        selectedTunnel?.isActive == true ? "Stop" : "Start"
    }

    private var isHostConnected: Bool {
        manager.runtimeState(for: host).isMasterRunning
    }

    private var connectionTitle: String {
        isHostConnected ? "Disconnect Host" : "Connect Host"
    }

}

private struct TunnelEditContext: Identifiable {
    let id = UUID()
    let hostId: UUID
    let tunnel: TunnelSpec
}
