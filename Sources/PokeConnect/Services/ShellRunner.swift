import Foundation

final class ShellRunner {
    private let shellPath = "/bin/zsh"

    func run(_ command: String, workingDirectory: String? = nil) async throws -> ShellResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.shellPath)
            process.arguments = ["-lc", command]

            if let workingDirectory, !workingDirectory.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            return ShellResult(
                command: command,
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }.value
    }
}
