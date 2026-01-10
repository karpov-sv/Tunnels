import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if manager.hostProfiles.isEmpty {
            Text("No hosts configured")
        } else {
            ForEach(manager.hostProfiles) { host in
                Menu {
                    Text("Status: \(manager.statusLabel(for: host))")

                    if host.tunnels.isEmpty {
                        Text("No tunnels")
                    } else {
                        ForEach(host.tunnels) { tunnel in
                            Button {
                                manager.toggleTunnel(hostId: host.id, tunnelId: tunnel.id)
                            } label: {
                                Label {
                                    Text(tunnelLabel(tunnel))
                                } icon: {
                                    MenuStatusDotView(state: tunnelIndicatorState(for: tunnel, manager: manager))
                                }
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    }

                    Divider()
                    Button("Start All Tunnels") {
                        Task {
                            await manager.startAllTunnels(hostId: host.id)
                        }
                    }
                    .disabled(!host.tunnels.contains(where: { !$0.isActive }))
                    Button(connectionTitle(for: host)) {
                        Task {
                            if isHostConnected(host) {
                                await manager.disconnectHost(id: host.id)
                            } else {
                                await manager.connectHost(id: host.id)
                            }
                        }
                    }
                } label: {
                    Label {
                        Text(host.alias)
                    } icon: {
                        MenuStatusDotView(state: hostIndicatorState(host))
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }

        Divider()
        Button("Logs...") {
            NSApp.activate(ignoringOtherApps: true)
            manager.preferencesTab = .logs
            openWindow(id: "preferences")
        }
        Button("Preferences...") {
            NSApp.activate(ignoringOtherApps: true)
            manager.preferencesTab = .general
            openWindow(id: "preferences")
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func tunnelLabel(_ tunnel: TunnelSpec) -> String {
        let action = tunnel.isActive ? "Stop" : "Start"
        return "\(action) \(tunnel.displaySummary)"
    }

    private func hostIndicatorState(_ host: HostProfile) -> TunnelIndicatorState {
        if manager.isHostReconnecting(host) {
            return .reconnecting
        }
        return manager.runtimeStateSnapshot(for: host).isMasterRunning ? .connected : .disconnected
    }

    private func isHostConnected(_ host: HostProfile) -> Bool {
        manager.runtimeStateSnapshot(for: host).isMasterRunning
    }

    private func connectionTitle(for host: HostProfile) -> String {
        isHostConnected(host) ? "Disconnect Host" : "Connect Host"
    }

}
