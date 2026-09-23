import Foundation

/// Well-known filesystem locations used by the CLI.
///
/// All of them can be redirected with environment variables so tests, CI and
/// power users can isolate state:
///
/// - `SHARE_CONFIG_DIR`   overrides the config directory (default `$XDG_CONFIG_HOME/share` or `~/.config/share`)
/// - `SHARE_TMPDIR`       overrides the scratch directory used for archives and staging
enum Paths {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Test hooks. When set they win over the environment.
    static var configDirectoryOverride: URL?
    static var tempDirectoryOverride: URL?

    /// Directory holding `config.json`, `aliases.json` and `history.json`.
    static var configDirectory: URL {
        if let override = configDirectoryOverride { return override }
        if let override = env["SHARE_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty, xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("share", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
    }

    static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    static var aliasesFile: URL { configDirectory.appendingPathComponent("aliases.json") }
    static var historyFile: URL { configDirectory.appendingPathComponent("history.json") }

    /// Project-local config file, looked up in the current working directory.
    static var localConfigFile: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".share.json")
    }

    /// Scratch directory for zips, staged copies, screenshots and QR images.
    static var tempDirectory: URL {
        if let override = tempDirectoryOverride { return override }
        if let override = env["SHARE_TMPDIR"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("share-cli", isDirectory: true)
    }

    /// Absolute path of the running executable, resolved even when invoked via `$PATH`.
    static var executableURL: URL {
        if let url = Bundle.main.executableURL, FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        let argv0 = CommandLine.arguments.first ?? "share"
        if argv0.contains("/") {
            return URL(fileURLWithPath: argv0).standardized
        }
        let searchPath = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for dir in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(argv0)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return URL(fileURLWithPath: argv0)
    }

    /// The user's home directory, standardized.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.standardized }

    static func ensureConfigDirectory() throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }
}
