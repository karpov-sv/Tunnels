import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var manager: TunnelManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager?.configureNotificationsIfNeeded()
    }

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
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(manager)
        } label: {
            MenuBarIconView(baseIcon: menuBarIcon())
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

    private func menuBarIcon() -> NSImage {
        guard let source = NSApplication.shared.applicationIconImage ?? NSImage(systemSymbolName: "link", accessibilityDescription: nil) else {
            return NSImage()
        }
        let targetSize = NSSize(width: 18, height: 18)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0)
        target.unlockFocus()
        target.isTemplate = true
        return target
    }
}
