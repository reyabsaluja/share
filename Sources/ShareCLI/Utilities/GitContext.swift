import Foundation

enum GitContext {
    static func repoName() -> String? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let gitDir = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return nil }
        return url.lastPathComponent
    }

    static func branchName() -> String? {
        return run("git", "rev-parse", "--abbrev-ref", "HEAD")
    }

    static func shortHash() -> String? {
        return run("git", "rev-parse", "--short", "HEAD")
    }

    static func isDirty() -> Bool {
        guard let output = run("git", "status", "--porcelain") else { return false }
        return !output.isEmpty
    }

    static func smartArchiveName() -> String {
        let base = repoName() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent
        if let branch = branchName(), branch != "main" && branch != "master" && branch != "HEAD" {
            return "\(base)-\(sanitize(branch))"
        }
        return base
    }

    static func smartSubject(for action: String = "Shared") -> String {
        let repo = repoName() ?? "files"
        if let branch = branchName(), branch != "main" && branch != "master" {
            return "\(action): \(repo) (\(branch))"
        }
        return "\(action): \(repo)"
    }

    static func diff() -> String? {
        return run("git", "--no-pager", "diff")
    }

    static func diffStaged() -> String? {
        return run("git", "--no-pager", "diff", "--staged")
    }

    private static func run(_ args: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func sanitize(_ branch: String) -> String {
        return branch
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
