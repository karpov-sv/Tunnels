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
                                    Text(tunnelLabel(tunnel, host: host))
                                } icon: {
                                    MenuStatusDotView(state: tunnelIndicatorState(for: tunnel, host: host, manager: manager))
                                }
                                .labelStyle(.titleAndIcon)
                            }
                            .disabled(manager.isTunnelOperationInProgress(tunnel.id))
                        }
                    }

                    Divider()
                    Button("Add Tunnel...") {
                        openWindow(id: "add-tunnel", value: host.id)
                    }
                    Button("Host Details...") {
                        openWindow(id: "host-details", value: host.id)
                    }
                    Button("Start All Tunnels") {
                        Task {
                            await manager.startAllTunnels(hostId: host.id)
                        }
                    }
                    .disabled(!host.tunnels.contains(where: { !$0.isActive }) || hostHasTunnelOperation(host))
                    Button("Stop All Tunnels") {
                        Task {
                            await manager.stopAllTunnels(hostId: host.id)
                        }
                    }
                    .disabled(!host.tunnels.contains(where: { $0.isActive }) || hostHasTunnelOperation(host))
                    Button(connectionTitle(for: host)) {
                        Task {
                            if shouldDisconnectHost(host) {
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
        Button("About...") {
            NSApp.activate(ignoringOtherApps: true)
            manager.preferencesTab = .about
            openWindow(id: "preferences")
        }
        Button("Preferences...") {
            NSApp.activate(ignoringOtherApps: true)
            manager.preferencesTab = .general
            openWindow(id: "preferences")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func tunnelLabel(_ tunnel: TunnelSpec, host: HostProfile) -> String {
        let shouldStop = manager.shouldStopTunnel(hostId: host.id, tunnelId: tunnel.id)
        let action = shouldStop ? "Stop" : "Start"
        return "\(action) \(tunnel.displaySummary)"
    }

    private func hostIndicatorState(_ host: HostProfile) -> TunnelIndicatorState {
        if manager.isHostReconnecting(host) {
            return .reconnecting
        }
        return manager.runtimeStateSnapshot(for: host).isMasterRunning ? .connected : .disconnected
    }

    private func shouldDisconnectHost(_ host: HostProfile) -> Bool {
        manager.shouldDisconnectHost(host)
    }

    private func hostHasTunnelOperation(_ host: HostProfile) -> Bool {
        host.tunnels.contains { manager.isTunnelOperationInProgress($0.id) }
    }

    private func connectionTitle(for host: HostProfile) -> String {
        shouldDisconnectHost(host) ? "Disconnect Host" : "Connect Host"
    }

}
