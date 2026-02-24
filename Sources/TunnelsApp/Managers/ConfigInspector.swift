import Foundation

final class ConfigInspector {
    func inspect(alias: String, sshPath: String) async -> ExecResult {
        await Task.detached {
            SSHProcessRunner.run(executablePath: sshPath, args: ["-G", alias])
        }.value
    }
}
