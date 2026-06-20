import Foundation

enum BundledServerInstaller {
    static let folderName = "mac-local-manager"

    static var installDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Poke Connect", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func installedPath() -> String {
        installDirectory.path
    }

    static func installIfNeeded() throws {
        let fileManager = FileManager.default
        let serverFile = installDirectory.appendingPathComponent("server.ts")
        let packageFile = installDirectory.appendingPathComponent("package.json")
        let tsNodeFile = installDirectory.appendingPathComponent("node_modules/.bin/ts-node")
        let pm2File = installDirectory.appendingPathComponent("node_modules/.bin/pm2")

        if fileManager.fileExists(atPath: serverFile.path),
           fileManager.fileExists(atPath: packageFile.path),
           fileManager.fileExists(atPath: tsNodeFile.path),
           fileManager.fileExists(atPath: pm2File.path),
           packageHasStartScript(at: packageFile) {
            return
        }

        try fileManager.createDirectory(
            at: installDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: installDirectory.path) {
            try fileManager.removeItem(at: installDirectory)
        }

        guard let bundledURL = Bundle.module.url(forResource: folderName, withExtension: nil) else {
            throw InstallerError.missingBundledServer
        }

        try fileManager.copyItem(at: bundledURL, to: installDirectory)
    }

    private static func packageHasStartScript(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any],
              let start = scripts["start"] as? String else {
            return false
        }

        return start.contains("server.ts")
    }
}

enum InstallerError: LocalizedError {
    case missingBundledServer

    var errorDescription: String? {
        switch self {
        case .missingBundledServer:
            return "Bundled mac-local-manager resource was not found in the app."
        }
    }
}
