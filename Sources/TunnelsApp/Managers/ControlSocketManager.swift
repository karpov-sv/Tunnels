import CryptoKit
import Foundation

final class ControlSocketManager {
    private let baseURL: URL
    private static let hashLength = 16
    private static let maxSocketPathLength = 100
    private static let randomSuffix = ".XXXXXXXXXXXXXXX"

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let defaultBase = appSupport?
            .appendingPathComponent("Tunnels", isDirectory: true)
            .appendingPathComponent("control", isDirectory: true)
        let tempBase = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("tunnels-control", isDirectory: true)

        let chosenBase: URL
        if let defaultBase, Self.fitsSocketPathLimit(baseURL: defaultBase) {
            chosenBase = defaultBase
        } else {
            chosenBase = tempBase
        }

        self.baseURL = chosenBase

        do {
            try fileManager.createDirectory(at: chosenBase, withIntermediateDirectories: true)
        } catch {
            NSLog("Failed to create control socket directory: \(error)")
        }
    }

    var basePath: String {
        baseURL.path
    }

    func socketPath(for alias: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(alias.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let shortHex = String(hex.prefix(Self.hashLength))
        return baseURL.appendingPathComponent("ctl-\(shortHex)").path
    }

    private static func fitsSocketPathLimit(baseURL: URL) -> Bool {
        let sampleName = "ctl-\(String(repeating: "a", count: hashLength))"
        let sample = baseURL.appendingPathComponent(sampleName).path + randomSuffix
        return sample.count <= maxSocketPathLength
    }
}
