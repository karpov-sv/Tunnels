import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var manager: TunnelManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager else { return .terminateNow }
        Task {
            await manager.shutdownAll()
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct TunnelsApp: App {
    @StateObject private var manager: TunnelManager
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let manager = TunnelManager()
        _manager = StateObject(wrappedValue: manager)
        appDelegate.manager = manager
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Tunnels", systemImage: "link") {
            MenuBarContent()
                .environmentObject(manager)
        }

        WindowGroup("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(manager)
        }

        WindowGroup("Add Host", id: "add-host") {
            AddHostView()
                .environmentObject(manager)
        }

        WindowGroup("Add Tunnel", id: "add-tunnel", for: UUID.self) { $hostId in
            AddTunnelView(hostId: $hostId)
                .environmentObject(manager)
        }

        WindowGroup("Host Details", id: "host-details", for: UUID.self) { $hostId in
            HostDetailsView(hostId: $hostId)
                .environmentObject(manager)
        }
    }
}
