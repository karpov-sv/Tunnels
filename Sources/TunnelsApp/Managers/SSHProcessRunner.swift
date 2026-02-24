import Foundation

struct ExecResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var success: Bool { exitCode == 0 }
    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum SSHProcessRunner {
    static func run(executablePath: String = "/usr/bin/ssh", args: [String]) -> ExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ExecResult(exitCode: -1, stdout: "", stderr: "Failed to run ssh: \(error)")
        }

        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ExecResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
