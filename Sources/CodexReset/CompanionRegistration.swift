import Foundation

/// Register the bundled helper after a drag-and-drop installation, without
/// requiring Python, Xcode, a shell installer, or administrator access.
enum CompanionRegistration {
    static func installIfNeeded() throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app",
              appURL.deletingLastPathComponent().lastPathComponent == "Applications" else { return }

        let label = "com.arthurbenfica.codexreset-companion"
        let helperURL = appURL.appendingPathComponent("Contents/MacOS/CodexResetCompanion")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { return }
        let agentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = agentsURL.appendingPathComponent(label + ".plist")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperURL.path, appURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "EnvironmentVariables": ["CODEX_RESET_COMPANION_VERSION": version],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        let domain = "gui/\(getuid())"
        if let existing = try? Data(contentsOf: plistURL),
           let previous = try? PropertyListSerialization.propertyList(from: existing, format: nil)
                as? NSDictionary,
           previous.isEqual(to: payload),
           try launchctl(["print", domain + "/" + label]) == 0 { return }

        try FileManager.default.createDirectory(at: agentsURL, withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        _ = try launchctl(["bootout", domain + "/" + label])
        let status = try launchctl(["bootstrap", domain, plistURL.path])
        guard status == 0 else {
            throw NSError(domain: "CodexReset.CompanionRegistration", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Não foi possível ativar o início automático."])
        }
    }

    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
