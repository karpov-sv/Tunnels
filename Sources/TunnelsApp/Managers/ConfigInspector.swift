import Foundation

final class ConfigInspector {
    func inspect(alias: String, sshPath: String) async -> ExecResult {
        await Task.detached {
            SSHProcessRunner.run(executablePath: sshPath, args: ["-G", alias])
        }.value
    }

    func parseConfig(_ output: String) -> [(String, String)] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces))
            }
    }
}
