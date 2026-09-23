import Foundation

/// Lightweight git queries used for naming archives and subjects. Every call is
/// best-effort: when git is missing or the directory is not a repository, the
/// functions return nil and callers fall back to plain names.
enum GitContext {
    /// The repository root containing `directory`, if any.
    static func repoRoot(for directory: URL? = nil) -> URL? {
        let dir = directory ?? cwd
        guard let output = run(in: dir, "rev-parse", "--show-toplevel"), !output.isEmpty else { return nil }
        return URL(fileURLWithPath: output, isDirectory: true).standardized
    }

    /// True when `directory` is itself the root of a git repository.
    static func isRepoRoot(_ directory: URL) -> Bool {
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    /// The name of the repository the current directory belongs to.
    static func repoName(for directory: URL? = nil) -> String? {
        return repoRoot(for: directory)?.lastPathComponent
    }

    static func branchName(for directory: URL? = nil) -> String? {
        guard let branch = run(in: directory ?? cwd, "rev-parse", "--abbrev-ref", "HEAD"), !branch.isEmpty else { return nil }
        return branch
    }

    static func shortHash(for directory: URL? = nil) -> String? {
        return run(in: directory ?? cwd, "rev-parse", "--short", "HEAD")
    }

    static func isDirty(for directory: URL? = nil) -> Bool {
        guard let output = run(in: directory ?? cwd, "status", "--porcelain") else { return false }
        return !output.isEmpty
    }

    /// Files git considers part of the project: tracked plus untracked-but-not-ignored.
    /// Returns nil when `directory` is not a repository root or git is unavailable.
    static func projectFiles(in directory: URL) -> [String]? {
        guard isRepoRoot(directory) else { return nil }
        guard let output = runRaw(in: directory, "ls-files", "-z", "--cached", "--others", "--exclude-standard") else { return nil }
        return output.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
    }

    /// Archive name for a directory: `repo` on main/master, `repo-branch` otherwise.
    static func archiveName(for directory: URL) -> String {
        let base = directory.lastPathComponent
        guard isRepoRoot(directory), let branch = branchName(for: directory), !isDefaultBranch(branch) else {
            return base
        }
        return "\(base)-\(sanitize(branch))"
    }

    /// Legacy helper kept for callers that operate on the current directory.
    static func smartArchiveName() -> String {
        return archiveName(for: cwd)
    }

    /// Subject line: "Shared: repo (branch)" or from the configured template.
    static func smartSubject(for action: String = "Shared", itemName: String? = nil) -> String {
        if let template = ShareConfig.current.subjectTemplate, !template.isEmpty {
            return SubjectTemplate.render(template, itemName: itemName)
        }
        let repo = repoName() ?? itemName ?? "files"
        if let branch = branchName(), !isDefaultBranch(branch) {
            return "\(action): \(repo) (\(branch))"
        }
        return "\(action): \(repo)"
    }

    static func diff(range: String? = nil, staged: Bool = false, paths: [String] = []) -> String? {
        var args = ["--no-pager", "diff"]
        if staged { args.append("--staged") }
        if let range = range { args.append(range) }
        if !paths.isEmpty { args.append("--"); args.append(contentsOf: paths) }
        return run(in: cwd, args)
    }

    static func diffStaged() -> String? {
        return diff(staged: true)
    }

    static var isAvailable: Bool {
        return run(in: cwd, "--version") != nil
    }

    static func isDefaultBranch(_ branch: String) -> Bool {
        return branch == "main" || branch == "master" || branch == "HEAD"
    }

    static func sanitize(_ branch: String) -> String {
        let cleaned = branch.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." { return ch }
            return "-"
        }
        return String(cleaned)
    }

    // MARK: - Process helpers

    private static var cwd: URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath) }

    private static func run(in directory: URL, _ args: String...) -> String? {
        return run(in: directory, args)
    }

    private static func run(in directory: URL, _ args: [String]) -> String? {
        return runRaw(in: directory, args)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runRaw(in directory: URL, _ args: String...) -> String? {
        return runRaw(in: directory, args)
    }

    private static func runRaw(in directory: URL, _ args: [String]) -> String? {
        let result = Subprocess.run("/usr/bin/env", arguments: ["git"] + args, currentDirectory: directory)
        guard result.status == 0 else { return nil }
        return result.stdout
    }
}

/// Renders `{repo}`, `{branch}`, `{name}`, `{date}`, `{time}`, `{user}`, `{host}` placeholders.
enum SubjectTemplate {
    static func render(_ template: String, itemName: String?, date: Date = Date()) -> String {
        let repo = GitContext.repoName() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent
        let branch = GitContext.branchName() ?? ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let values: [String: String] = [
            "repo": repo,
            "branch": branch,
            "name": itemName ?? repo,
            "date": dateFormatter.string(from: date),
            "time": timeFormatter.string(from: date),
            "user": NSUserName(),
            "host": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        ]
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        // Tidy the common "repo ()" case when there is no branch.
        return result.replacingOccurrences(of: " ()", with: "").trimmingCharacters(in: .whitespaces)
    }
}
