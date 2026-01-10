import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    let entries: [LogEntry]

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.isRichText = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let attributed = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        for (index, entry) in entries.enumerated() {
            let color: NSColor = entry.level == .error ? .systemRed : .labelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font
            ]
            attributed.append(NSAttributedString(string: entry.formattedLine, attributes: attributes))
            if index < entries.count - 1 {
                attributed.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }
}
