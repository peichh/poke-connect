import Foundation

enum ServiceStatus: String {
    case running = "Running"
    case stopped = "Stopped"
}

enum OverallStatus: String {
    case online = "Online"
    case offline = "Offline"
    case starting = "Starting"
    case error = "Error"
}

struct ShellResult: Sendable {
    let command: String
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
