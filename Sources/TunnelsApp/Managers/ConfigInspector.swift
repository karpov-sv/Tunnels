import Foundation

final class ConfigInspector {
    func inspect(hostname: String, sshPath: String) async -> ExecResult {
        await Task.detached {
            SSHProcessRunner.run(executablePath: sshPath, args: ["-G", hostname])
        }.value
    }
}
