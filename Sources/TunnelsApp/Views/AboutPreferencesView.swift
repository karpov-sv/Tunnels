import AppKit
import SwiftUI

struct AboutPreferencesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIconImage)
                .renderingMode(.original)
                .resizable()
                .frame(width: 96, height: 96)
                .cornerRadius(18)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(versionLine)
                    .foregroundStyle(.secondary)
            }

            Text("Menu bar SSH tunnel manager for macOS.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Tunnels"
    }

    private var versionLine: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(build))"
    }

    private var appIconImage: NSImage {
        let info = Bundle.main.infoDictionary ?? [:]
        let iconName = info["CFBundleIconName"] as? String
        let iconFile = info["CFBundleIconFile"] as? String

        if let iconName, let image = NSImage(named: iconName) {
            return nonTemplate(image)
        }
        if let iconFile {
            if let image = NSImage(named: iconFile) {
                return nonTemplate(image)
            }
            let base = (iconFile as NSString).deletingPathExtension
            if let path = Bundle.main.path(forResource: base, ofType: "icns"),
               let image = NSImage(contentsOfFile: path) {
                return nonTemplate(image)
            }
        }
        return nonTemplate(NSApplication.shared.applicationIconImage)
    }

    private func nonTemplate(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.isTemplate = false
        return copy
    }
}
