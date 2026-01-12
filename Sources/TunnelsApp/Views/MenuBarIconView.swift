import AppKit
import SwiftUI

struct MenuBarIconView: View {
    @EnvironmentObject private var manager: TunnelManager
    @Environment(\.colorScheme) private var colorScheme
    let baseIcon: NSImage

    private let iconSize = NSSize(width: 18, height: 18)
    private let dotSize: CGFloat = 4
    private let dotInset: CGFloat = 1

    var body: some View {
        Image(nsImage: statusImage(colorScheme: colorScheme))
            .resizable()
            .renderingMode(.original)
            .frame(width: iconSize.width, height: iconSize.height)
            .accessibilityLabel(accessibilityLabel)
    }

    private var indicatorState: TunnelIndicatorState? {
        if !manager.reconnectingHosts.isEmpty {
            return .reconnecting
        }
        let hasConnectedHost = manager.hostProfiles.contains { host in
            manager.runtimeStateSnapshot(for: host).isMasterRunning
        }
        if hasConnectedHost {
            return .connected
        }
        return nil
    }

    private var accessibilityLabel: String {
        guard let indicatorState else { return "Tunnels" }
        return "Tunnels, \(indicatorState.label)"
    }

    private func statusImage(colorScheme: ColorScheme) -> NSImage {
        let image = NSImage(size: iconSize)
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        let drawBlock = {
            image.lockFocus()
            let rect = NSRect(origin: .zero, size: iconSize)
            NSColor.labelColor.setFill()
            NSBezierPath(rect: rect).fill()
            baseIcon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            if let indicatorState {
                let dotRect = NSRect(
                    x: 0,
                    y: iconSize.height - dotSize,
                    width: dotSize,
                    height: dotSize
                )
                indicatorState.nsColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            image.unlockFocus()
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                drawBlock()
            }
        } else {
            drawBlock()
        }
        image.isTemplate = false
        return image
    }
}
