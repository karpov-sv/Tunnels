import AppKit
import SwiftUI

enum TunnelIndicatorState {
    case connected
    case disconnected
    case reconnecting
    case warning
    case error

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .orange
        case .reconnecting:
            return .blue
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .connected:
            return .systemGreen
        case .disconnected:
            return .systemOrange
        case .reconnecting:
            return .systemBlue
        case .warning:
            return .systemYellow
        case .error:
            return .systemRed
        }
    }

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .reconnecting:
            return "Reconnecting"
        case .warning:
            return "Port in use"
        case .error:
            return "Error"
        }
    }
}

struct StatusDotView: View {
    let state: TunnelIndicatorState

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8, weight: .regular))
            .foregroundStyle(state.color)
            .accessibilityLabel(state.label)
    }
}

struct TunnelStatusCell: View {
    let state: TunnelIndicatorState

    var body: some View {
        HStack(spacing: 6) {
            StatusDotView(state: state)
            Text(state.label)
        }
    }
}

struct MenuStatusDotView: View {
    let state: TunnelIndicatorState

    var body: some View {
        Image(nsImage: MenuStatusDotCache.image(for: state))
            .accessibilityLabel(state.label)
    }
}

private enum MenuStatusDotCache {
    private static let size = NSSize(width: 10, height: 10)
    private static let connected = make(color: .systemGreen)
    private static let disconnected = make(color: .systemOrange)
    private static let reconnecting = make(color: .systemBlue)
    private static let warning = make(color: .systemYellow)
    private static let error = make(color: .systemRed)

    static func image(for state: TunnelIndicatorState) -> NSImage {
        switch state {
        case .connected:
            return connected
        case .disconnected:
            return disconnected
        case .reconnecting:
            return reconnecting
        case .warning:
            return warning
        case .error:
            return error
        }
    }

    private static func make(color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

@MainActor
func tunnelIndicatorState(for tunnel: TunnelSpec, host: HostProfile, manager: TunnelManager) -> TunnelIndicatorState {
    if manager.isHostReconnecting(host) {
        return .reconnecting
    }
    if tunnel.isActive {
        return .connected
    }
    if manager.tunnelHasError(tunnel.id) {
        return .error
    }
    if tunnel.type != .remote, manager.localPortInUse(tunnel.localPort) {
        return .warning
    }
    return .disconnected
}
