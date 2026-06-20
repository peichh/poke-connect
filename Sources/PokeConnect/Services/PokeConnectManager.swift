import AppKit
import Foundation
import ServiceManagement

@MainActor
final class PokeConnectManager: ObservableObject {
    @Published var serverStatus: ServiceStatus = .stopped
    @Published var tunnelStatus: ServiceStatus = .stopped
    @Published var overallStatus: OverallStatus = .offline
    @Published var lastError = ""
    @Published var logs = ""

    @Published var startAtLogin: Bool {
        didSet {
            guard oldValue != startAtLogin else { return }
            UserDefaults.standard.set(startAtLogin, forKey: Defaults.startAtLogin)
            Task { await applyStartAtLoginPreference() }
        }
    }

    @Published var autoConnectOnLaunch: Bool {
        didSet { UserDefaults.standard.set(autoConnectOnLaunch, forKey: Defaults.autoConnectOnLaunch) }
    }

    @Published var customServerCommand: String {
        didSet { UserDefaults.standard.set(customServerCommand, forKey: Defaults.customServerCommand) }
    }

    @Published var customNgrokCommand: String {
        didSet { UserDefaults.standard.set(customNgrokCommand, forKey: Defaults.customNgrokCommand) }
    }

    @Published var workingDirectory: String {
        didSet { UserDefaults.standard.set(workingDirectory, forKey: Defaults.workingDirectory) }
    }

    @Published var pm2CommandPath: String {
        didSet { UserDefaults.standard.set(pm2CommandPath, forKey: Defaults.pm2CommandPath) }
    }

    @Published var ngrokCommandPath: String {
        didSet { UserDefaults.standard.set(ngrokCommandPath, forKey: Defaults.ngrokCommandPath) }
    }

    @Published var ngrokDomain: String {
        didSet {
            UserDefaults.standard.set(ngrokDomain, forKey: Defaults.ngrokDomain)
            if oldValue != ngrokDomain,
               customNgrokCommand.contains(oldValue) || customNgrokCommand.contains(Self.placeholderDomain) || customNgrokCommand.isEmpty {
                customNgrokCommand = defaultTunnelCommand()
            }
        }
    }

    @Published var discoveredPublicURL: String {
        didSet { UserDefaults.standard.set(discoveredPublicURL, forKey: Defaults.discoveredPublicURL) }
    }

    @Published var ngrokAuthtoken: String {
        didSet {
            UserDefaults.standard.set(ngrokAuthtoken, forKey: Defaults.ngrokAuthtoken)
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != ngrokAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines) {
                ngrokAuthtokenConfigured = false
            }
        }
    }

    @Published var ngrokAuthtokenConfigured: Bool {
        didSet { UserDefaults.standard.set(ngrokAuthtokenConfigured, forKey: Defaults.ngrokAuthtokenConfigured) }
    }

    @Published var pokeIntegrationConnected: Bool {
        didSet { UserDefaults.standard.set(pokeIntegrationConnected, forKey: Defaults.pokeIntegrationConnected) }
    }

    let ngrokAuthtokenURL = URL(string: "https://dashboard.ngrok.com/get-started/your-authtoken")!
    let pokeIntegrationURL = URL(string: "https://poke.com/integrations/new")!
    let defaultWorkingDirectory = BundledServerInstaller.installedPath()
    private static let placeholderDomain = "your-ngrok-domain.ngrok-free.dev"
    private static let ngrokLogFile = "ngrok.log"

    private let runner = ShellRunner()
    private var refreshTask: Task<Void, Never>?
    private let bundledPM2Path = "./node_modules/.bin/pm2"

    private enum Defaults {
        static let startAtLogin = "startAtLogin"
        static let autoConnectOnLaunch = "autoConnectOnLaunch"
        static let customServerCommand = "customServerCommand"
        static let customNgrokCommand = "customNgrokCommand"
        static let workingDirectory = "workingDirectory"
        static let pm2CommandPath = "pm2CommandPath"
        static let ngrokCommandPath = "ngrokCommandPath"
        static let ngrokDomain = "ngrokDomain"
        static let discoveredPublicURL = "discoveredPublicURL"
        static let ngrokAuthtoken = "ngrokAuthtoken"
        static let ngrokAuthtokenConfigured = "ngrokAuthtokenConfigured"
        static let pokeIntegrationConnected = "pokeIntegrationConnected"
    }

    private enum Commands {
        static let server = "pm2 start npm --name \"mac-local-server\" -- start"
        static let legacyServer = "pm2 start npx --name \"mac-local-server\" -- ts-node server.ts"
        static let stopServer = "pm2 stop mac-local-server"
    }

    init() {
        do {
            try BundledServerInstaller.installIfNeeded()
        } catch {
            self.lastError = error.localizedDescription
            self.logs = "Bundled server install error: \(error.localizedDescription)\n"
        }

        let defaults = UserDefaults.standard
        self.startAtLogin = defaults.bool(forKey: Defaults.startAtLogin)
        self.autoConnectOnLaunch = defaults.bool(forKey: Defaults.autoConnectOnLaunch)
        let storedServerCommand = defaults.string(forKey: Defaults.customServerCommand) ?? ""
        self.customServerCommand = storedServerCommand.isEmpty || storedServerCommand == Commands.legacyServer
            ? Commands.server
            : storedServerCommand
        let storedDomain = defaults.string(forKey: Defaults.ngrokDomain) ?? ""
        let initialNgrokDomain = storedDomain == Self.placeholderDomain ? "" : storedDomain
        self.ngrokDomain = initialNgrokDomain
        self.discoveredPublicURL = defaults.string(forKey: Defaults.discoveredPublicURL) ?? ""
        let storedTunnelCommand = defaults.string(forKey: Defaults.customNgrokCommand) ?? ""
        self.customNgrokCommand = storedTunnelCommand.isEmpty
            ? ""
            : storedTunnelCommand

        let storedDir = defaults.string(forKey: Defaults.workingDirectory) ?? ""
        let trimmedDir = storedDir.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workingDirectory = trimmedDir.isEmpty
            ? BundledServerInstaller.installedPath()
            : storedDir

        let storedPM2Path = defaults.string(forKey: Defaults.pm2CommandPath) ?? ""
        self.pm2CommandPath = storedPM2Path.isEmpty || storedPM2Path == "pm2"
            ? bundledPM2Path
            : storedPM2Path
        self.ngrokCommandPath = defaults.string(forKey: Defaults.ngrokCommandPath) ?? "ngrok"
        self.ngrokAuthtoken = defaults.string(forKey: Defaults.ngrokAuthtoken) ?? ""
        self.ngrokAuthtokenConfigured = defaults.bool(forKey: Defaults.ngrokAuthtokenConfigured)
        self.pokeIntegrationConnected = defaults.bool(forKey: Defaults.pokeIntegrationConnected)

        startStatusRefresh()

        if autoConnectOnLaunch && ngrokAuthtokenConfigured {
            Task { await connect() }
        } else {
            Task { await refreshStatus() }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var menuBarSystemImage: String {
        switch overallStatus {
        case .online:
            "link"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .error:
            "exclamationmark.triangle"
        case .offline:
            "link.badge.plus"
        }
    }

    var connectButtonTitle: String {
        overallStatus == .online ? "Disconnect" : "Connect"
    }

    var publicHost: String {
        guard let host = URL(string: publicURL)?.host else {
            return configuredNgrokDomain
        }

        return host
    }

    var publicURL: String {
        let discovered = discoveredPublicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !discovered.isEmpty {
            return discovered
        }

        let domain = configuredNgrokDomain
        return domain.isEmpty ? "" : "https://\(domain)"
    }

    var mcpURL: String {
        publicURL.isEmpty ? "" : "\(publicURL)/sse"
    }

    var isSetupComplete: Bool {
        ngrokAuthtokenConfigured && pokeIntegrationConnected
    }

    var setupStatusMessage: String {
        if !ngrokAuthtokenConfigured {
            return "Add and save your ngrok authtoken before using Poke Connect."
        }

        if !pokeIntegrationConnected && (tunnelStatus != .running || mcpURL.isEmpty) {
            return "Start the bridge first so ngrok can generate the MCP URL."
        }

        if !pokeIntegrationConnected {
            return "Connect the generated MCP URL to Poke, then confirm it here."
        }

        return "Setup complete."
    }

    func connectOrDisconnect() async {
        if overallStatus == .online {
            await disconnect()
        } else {
            await connect()
        }
    }

    func connect() async {
        overallStatus = .starting
        lastError = ""
        appendLog("Connecting Poke bridge...")

        do {
            try validateNgrokConfigured()
            await refreshStatus()

            if serverStatus != .running {
                try validateWorkingDirectoryForServerCommand()
                await deleteStaleServerProcesses()
                try await runCommand(effectiveServerCommand(), workingDirectory: effectiveWorkingDirectory(), label: "Start server")
            }

            await refreshStatus()

            if tunnelStatus != .running {
                try validateNgrokAuthtoken()
                try await runCommand(effectiveTunnelCommand(), workingDirectory: nil, label: "Start tunnel")
                try await waitForNgrokPublicURL()
            }

            await refreshStatus()
        } catch {
            handle(error)
        }
    }

    func disconnect() async {
        overallStatus = .starting
        lastError = ""
        appendLog("Disconnecting Poke bridge...")

        do {
            _ = try? await runCommand(stopTunnelCommand(), workingDirectory: nil, label: "Stop tunnel")
            _ = try? await runCommand(stopServerCommand(), workingDirectory: effectiveWorkingDirectory(), label: "Stop server")
            await refreshStatus()
        }
    }

    func restart() async {
        appendLog("Restarting Poke bridge...")
        guard ngrokAuthtokenConfigured else {
            handle(PokeConnectError.setupIncomplete(setupStatusMessage))
            return
        }
        await disconnect()
        await connect()
    }

    func refreshStatus() async {
        do {
            async let server = checkServerRunning()
            async let tunnel = checkTunnelRunning()
            serverStatus = try await server ? .running : .stopped
            tunnelStatus = try await tunnel ? .running : .stopped
            updateOverallStatus()
        } catch {
            handle(error)
        }
    }

    func loadLogs() async {
        appendLog("Loading recent PM2 logs...")

        do {
            let pm2Logs = try await runner.run(
                "\(pm2CommandPath.shellQuoted) logs mac-local-server --lines 120 --nostream",
                workingDirectory: effectiveWorkingDirectory()
            )
            appendLog("PM2 logs:\n\(pm2Logs.combinedOutput)")
            await appendNgrokProcessDetails()
        } catch {
            handle(error)
        }
    }

    func copyURL() {
        guard !mcpURL.isEmpty else {
            handle(PokeConnectError.setupIncomplete("Start the bridge first so ngrok can generate the MCP URL."))
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpURL, forType: .string)
        appendLog("Copied \(mcpURL) to clipboard.")
    }

    func openNgrokAuthtokenPage() {
        NSWorkspace.shared.open(ngrokAuthtokenURL)
    }

    func openPokeIntegrationPage() {
        NSWorkspace.shared.open(pokeIntegrationURL)
    }

    func configureNgrokAuthtoken() async {
        do {
            try validateNgrokAuthtoken()
            appendLog("$ \(ngrokCommandPath.shellQuoted) config add-authtoken [redacted]")
            let result = try await runner.run(
                "\(ngrokCommandPath.shellQuoted) config add-authtoken \(ngrokAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines).shellQuoted)"
            )
            appendCommandResult(result, label: "Configure ngrok authtoken")
            guard result.exitCode == 0 else {
                throw PokeConnectError.commandFailed(label: "Configure ngrok authtoken", output: result.combinedOutput)
            }
            ngrokAuthtokenConfigured = true
            lastError = ""
            appendLog("ngrok authtoken is configured.")
        } catch {
            handle(error)
        }
    }

    func markPokeIntegrationConnected() {
        pokeIntegrationConnected = true
        lastError = ""
        appendLog("Poke MCP integration marked connected.")
    }

    func resetSetup() {
        ngrokAuthtokenConfigured = false
        pokeIntegrationConnected = false
        appendLog("Setup status reset.")
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func resetCommandsToDefaults() {
        customServerCommand = Commands.server
        customNgrokCommand = defaultTunnelCommand()
    }

    func useBundledServerFolder() {
        do {
            try BundledServerInstaller.installIfNeeded()
            workingDirectory = BundledServerInstaller.installedPath()
            customServerCommand = Commands.server
            pm2CommandPath = bundledPM2Path
            appendLog("Using bundled server folder: \(workingDirectory)")
        } catch {
            handle(error)
        }
    }

    private func startStatusRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.refreshStatus()
            }
        }
    }

    private func checkServerRunning() async throws -> Bool {
        let result = try await runner.run("\(pm2CommandPath.shellQuoted) jlist", workingDirectory: effectiveWorkingDirectory())
        guard result.exitCode == 0 else { return false }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return result.stdout.contains("mac-local-server") && result.stdout.contains("online")
        }

        return json.contains { process in
            guard process["name"] as? String == "mac-local-server" else { return false }
            if let pm2Env = process["pm2_env"] as? [String: Any],
               let status = pm2Env["status"] as? String {
                return status == "online" || status == "launching"
            }
            return false
        }
    }

    private func checkTunnelRunning() async throws -> Bool {
        await refreshNgrokPublicURL()
        let result = try await runner.run(ngrokProcessListCommand())
        return result.stdout.contains("ngrok") && (result.stdout.contains("http 3000") || result.stdout.contains("http --url="))
    }

    @discardableResult
    private func runCommand(_ command: String, workingDirectory: String?, label: String) async throws -> ShellResult {
        appendLog("$ \(command)")
        let result = try await runner.run(command, workingDirectory: workingDirectory)
        appendCommandResult(result, label: label)

        guard result.exitCode == 0 else {
            throw PokeConnectError.commandFailed(label: label, output: result.combinedOutput)
        }

        return result
    }

    private func appendCommandResult(_ result: ShellResult, label: String) {
        let output = result.combinedOutput
        appendLog("\(label) finished with exit code \(result.exitCode).")
        if !output.isEmpty {
            appendLog(output)
        }
    }

    private func appendNgrokProcessDetails() async {
        do {
            let result = try await runner.run(ngrokProcessListCommand())
            let output = result.combinedOutput.isEmpty ? "No ngrok process output found." : result.combinedOutput
            appendLog("ngrok processes:\n\(output)")
        } catch {
            appendLog("Unable to read ngrok process output: \(error.localizedDescription)")
        }
    }

    private func updateOverallStatus() {
        if !lastError.isEmpty {
            overallStatus = .error
        } else if serverStatus == .running && tunnelStatus == .running {
            overallStatus = .online
        } else {
            overallStatus = .offline
        }
    }

    private func handle(_ error: Error) {
        lastError = error.localizedDescription
        overallStatus = .error
        appendLog("Error: \(error.localizedDescription)")
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)\n")
    }

    private func effectiveWorkingDirectory() -> String? {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultWorkingDirectory : workingDirectory
    }

    private func validateWorkingDirectoryForServerCommand() throws {
        guard effectiveServerCommand().contains("server.ts") else { return }
        guard let directory = effectiveWorkingDirectory(), !directory.isEmpty else {
            throw PokeConnectError.invalidWorkingDirectory("Set Working directory to the folder that contains server.ts.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PokeConnectError.invalidWorkingDirectory("Working directory does not exist: \(directory)")
        }

        let serverPath = URL(fileURLWithPath: directory).appendingPathComponent("server.ts").path
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw PokeConnectError.invalidWorkingDirectory("Cannot find server.ts in Working directory: \(directory)")
        }
    }

    private func validateNgrokAuthtoken() throws {
        let trimmed = ngrokAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PokeConnectError.missingNgrokAuthtoken("Enter your ngrok authtoken in Settings first. Get one at \(ngrokAuthtokenURL.absoluteString)")
        }
    }

    private func validateNgrokConfigured() throws {
        guard ngrokAuthtokenConfigured else {
            throw PokeConnectError.setupIncomplete("Save your ngrok authtoken in Settings first.")
        }
    }

    private func deleteStaleServerProcesses() async {
        do {
            let result = try await runner.run("\(pm2CommandPath.shellQuoted) jlist", workingDirectory: effectiveWorkingDirectory())
            guard result.stdout.contains("mac-local-server"),
                  !result.stdout.contains("\"status\":\"online\""),
                  !result.stdout.contains("\"status\":\"launching\"") else {
                return
            }

            appendLog("Deleting stale PM2 entries for mac-local-server before starting.")
            _ = try? await runCommand(
                "\(pm2CommandPath.shellQuoted) delete mac-local-server",
                workingDirectory: effectiveWorkingDirectory(),
                label: "Delete stale server"
            )
        } catch {
            appendLog("Unable to inspect stale PM2 entries: \(error.localizedDescription)")
        }
    }

    private func effectiveServerCommand() -> String {
        replaceLeadingBinary(in: customServerCommand, defaultBinary: "pm2", configuredPath: pm2CommandPath)
    }

    private func effectiveTunnelCommand() -> String {
        if customNgrokCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            customNgrokCommand.contains(Self.placeholderDomain) {
            return defaultTunnelCommand()
        }
        return replaceLeadingBinary(in: customNgrokCommand, defaultBinary: "ngrok", configuredPath: ngrokCommandPath)
    }

    private func stopServerCommand() -> String {
        replaceLeadingBinary(in: Commands.stopServer, defaultBinary: "pm2", configuredPath: pm2CommandPath)
    }

    private func stopTunnelCommand() -> String {
        let escapedHost = publicHost.replacingOccurrences(of: ".", with: "[.]")
        guard !escapedHost.isEmpty else {
            return "pids=$(ps ax -o pid= -o command= | awk '/[n]grok/ && /http/ && /3000/ {print $1}'); if [ -n \"$pids\" ]; then kill $pids; fi"
        }

        return """
        pids=$(ps ax -o pid= -o command= | awk '/[n]grok/ && (/\(escapedHost)/ || (/http/ && /3000/)) {print $1}'); if [ -n "$pids" ]; then kill $pids; fi
        """
    }

    private func ngrokProcessListCommand() -> String {
        "ps ax -o pid= -o command= | grep '[n]grok' || true"
    }

    private func defaultTunnelCommand() -> String {
        let domain = configuredNgrokDomain
        let domainArgument = domain.isEmpty ? "" : " --url=\(domain)"
        let logPath = ngrokLogURL.path.shellQuoted
        return "mkdir -p \(applicationSupportDirectory.path.shellQuoted) && nohup \(ngrokCommandPath.shellQuoted) http\(domainArgument) 3000 > \(logPath) 2>&1 &"
    }

    private var configuredNgrokDomain: String {
        let trimmed = ngrokDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == Self.placeholderDomain ? "" : trimmed
    }

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Poke Connect", isDirectory: true)
    }

    private var ngrokLogURL: URL {
        applicationSupportDirectory.appendingPathComponent(Self.ngrokLogFile)
    }

    private func waitForNgrokPublicURL() async throws {
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            await refreshNgrokPublicURL()
            if !discoveredPublicURL.isEmpty {
                appendLog("ngrok public URL: \(discoveredPublicURL)")
                return
            }
        }
    }

    private func refreshNgrokPublicURL() async {
        if let apiURL = try? await readNgrokAPIURL() {
            discoveredPublicURL = apiURL
            return
        }

        if let logURL = try? await readNgrokLogURL() {
            discoveredPublicURL = logURL
        }
    }

    private func readNgrokAPIURL() async throws -> String? {
        let result = try await runner.run("curl -fsS http://127.0.0.1:4040/api/tunnels 2>/dev/null || true")
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tunnels = json["tunnels"] as? [[String: Any]] else {
            return nil
        }

        return tunnels.compactMap { tunnel in
            tunnel["public_url"] as? String
        }
        .first { $0.hasPrefix("https://") }
    }

    private func readNgrokLogURL() async throws -> String? {
        let result = try await runner.run("grep -Eo 'https://[^ ]+\\.ngrok[^ ]+' \(ngrokLogURL.path.shellQuoted) 2>/dev/null | tail -1 || true")
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    private func replaceLeadingBinary(in command: String, defaultBinary: String, configuredPath: String) -> String {
        guard command == defaultBinary || command.hasPrefix("\(defaultBinary) ") else { return command }
        return configuredPath.shellQuoted + command.dropFirst(defaultBinary.count)
    }

    private func applyStartAtLoginPreference() async {
        guard #available(macOS 13.0, *) else {
            lastError = "Start at Login requires macOS 13 or later."
            return
        }

        do {
            if startAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Unable to update Start at Login: \(error.localizedDescription)"
            logs.append("Start at Login error: \(error.localizedDescription)\n")
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

enum PokeConnectError: LocalizedError {
    case commandFailed(label: String, output: String)
    case invalidWorkingDirectory(String)
    case missingNgrokAuthtoken(String)
    case setupIncomplete(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(label, output):
            let detail = output.isEmpty ? "No output was returned." : output
            return "\(label) failed. \(detail)"
        case let .invalidWorkingDirectory(message):
            return message
        case let .missingNgrokAuthtoken(message):
            return message
        case let .setupIncomplete(message):
            return message
        }
    }
}
