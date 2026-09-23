import Foundation
import Testing
@testable import share

/// Root suite. `.serialized` is inherited by every nested suite, which matters because the
/// CLI keeps process-wide state (config cache, prompt overrides, path overrides).
@Suite(.serialized) enum ShareTests {}

/// A throwaway directory that also isolates config, history, aliases and scratch files.
final class Sandbox {
    let root: URL
    let config: URL
    let temp: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-tests-\(UUID().uuidString)", isDirectory: true)
        config = root.appendingPathComponent("config", isDirectory: true)
        temp = root.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        Paths.configDirectoryOverride = config
        Paths.tempDirectoryOverride = temp
        ShareConfig.invalidate()
        Prompt.assumeYes = false
        Prompt.answerOverride = nil
        Log.quiet = true
    }

    deinit {
        Paths.configDirectoryOverride = nil
        Paths.tempDirectoryOverride = nil
        Prompt.assumeYes = false
        Prompt.answerOverride = nil
        Log.quiet = false
        ShareConfig.invalidate()
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ relative: String, _ contents: String = "hello") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func directory(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Entry names inside a zip, via `unzip -Z1`.
    static func zipEntries(_ zip: URL) -> [String] {
        let result = Subprocess.run("/usr/bin/unzip", arguments: ["-Z1", zip.path])
        return result.stdout.split(separator: "\n").map(String.init)
    }

    @discardableResult
    static func git(_ dir: URL, _ args: String...) -> Subprocess.Result {
        return Subprocess.run("/usr/bin/env", arguments: ["git"] + args, currentDirectory: dir, environment: [
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "HOME": dir.path,
            "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t.t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t.t",
            "GIT_CONFIG_NOSYSTEM": "1",
        ])
    }
}
