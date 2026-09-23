import Foundation

/// One line of a `.shareignore` file (or a built-in rule), parsed with gitignore-like semantics:
///
/// - `name`        matches a file or directory called `name` at any depth
/// - `*.log`       wildcards use shell glob rules
/// - `build/`      trailing slash: directories only
/// - `/dist`       leading slash: anchored to the shared directory root
/// - `docs/*.pdf`  a slash in the middle also anchors the pattern to the root
/// - `!keep.log`   negation re-includes a previously excluded path (last match wins)
/// - `# comment`   comments and blank lines are ignored
struct IgnorePattern: Equatable {
    let pattern: String
    let negated: Bool
    let anchored: Bool
    let directoryOnly: Bool

    init?(line: String) {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }

        var negated = false
        if text.hasPrefix("!") {
            negated = true
            text.removeFirst()
        }
        if text.hasPrefix("\\") { text.removeFirst() }

        var directoryOnly = false
        if text.hasSuffix("/") {
            directoryOnly = true
            text.removeLast()
        }

        var anchored = false
        if text.hasPrefix("/") {
            anchored = true
            text.removeFirst()
        } else if text.contains("/") {
            anchored = true
        }
        if text.hasPrefix("**/") {
            anchored = false
            text.removeFirst(3)
        }

        guard !text.isEmpty else { return nil }
        self.pattern = text
        self.negated = negated
        self.anchored = anchored
        self.directoryOnly = directoryOnly
    }

    /// Does this pattern match `relativePath` (whose last component is `basename`)?
    func matches(relativePath: String, basename: String, isDirectory: Bool) -> Bool {
        if directoryOnly && !isDirectory { return false }
        if anchored {
            return Glob.fnmatch(pattern, relativePath) || Glob.fnmatch(pattern + "/*", relativePath)
        }
        return Glob.fnmatch(pattern, basename)
    }
}

enum Glob {
    /// Shell-style matching. `*` also crosses `/`, which keeps `docs/**/*.md`-style patterns useful.
    static func fnmatch(_ pattern: String, _ string: String) -> Bool {
        let normalized = pattern.replacingOccurrences(of: "**/", with: "*").replacingOccurrences(of: "/**", with: "*")
        return Darwin.fnmatch(normalized, string, 0) == 0
    }

    static func parse(_ lines: [String]) -> [IgnorePattern] {
        return lines.compactMap(IgnorePattern.init(line:))
    }

    static func parse(_ text: String) -> [IgnorePattern] {
        return parse(text.components(separatedBy: .newlines))
    }

    /// Evaluates a path (and every ancestor directory) against the rules. Last matching rule wins;
    /// a path inside an excluded directory cannot be re-included, matching gitignore.
    static func isIgnored(relativePath: String, isDirectory: Bool, patterns: [IgnorePattern]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }

        for depth in 1...components.count {
            let subpath = components[0..<depth].joined(separator: "/")
            let isDir = depth < components.count || isDirectory
            var ignored = false
            for pattern in patterns where pattern.matches(relativePath: subpath, basename: components[depth - 1], isDirectory: isDir) {
                ignored = !pattern.negated
            }
            if ignored { return true }
        }
        return false
    }
}

/// The complete set of exclusions applied when staging a directory in smart mode.
struct ExcludeRules {
    var patterns: [IgnorePattern]

    static let none = ExcludeRules(patterns: [])

    /// Names that are never useful to share, regardless of project type.
    static let alwaysExcluded: [String] = [
        ".git", ".hg", ".svn", ".DS_Store", "Thumbs.db", "desktop.ini",
        ".env", ".env.*", "!.env.example", "!.env.sample", "!.env.template",
        "node_modules", ".build", ".swiftpm", "DerivedData", "__pycache__",
        ".pytest_cache", ".mypy_cache", ".ruff_cache", "target", "dist", ".next", ".nuxt",
        "Pods", ".gradle", "build", "venv", ".venv", ".cache", ".parcel-cache",
        ".turbo", ".idea", ".vscode", "*.pyc", "*.log", ".terraform", ".direnv",
    ]

    init(patterns: [IgnorePattern]) {
        self.patterns = patterns
    }

    init(lines: [String]) {
        self.patterns = Glob.parse(lines)
    }

    /// Built-in rules + project-type rules + `.shareignore` in `directory` + extra user patterns.
    static func smart(for directory: URL, projectType: ProjectType? = nil, extra: [String] = []) -> ExcludeRules {
        let type = projectType ?? ProjectDetector.detect(at: directory)
        var lines = alwaysExcluded
        lines.append(contentsOf: ProjectDetector.excludes(for: type))
        lines.append(contentsOf: ShareIgnoreFile.lines(in: directory))
        lines.append(contentsOf: extra)
        return ExcludeRules(lines: lines)
    }

    /// Only the user's explicit patterns (`--exclude`) plus `.shareignore`. Used when smart mode is off.
    static func explicit(for directory: URL, extra: [String]) -> ExcludeRules {
        var lines = [".git", ".DS_Store"]
        lines.append(contentsOf: ShareIgnoreFile.lines(in: directory))
        lines.append(contentsOf: extra)
        return ExcludeRules(lines: lines)
    }

    func isExcluded(relativePath: String, isDirectory: Bool) -> Bool {
        return Glob.isIgnored(relativePath: relativePath, isDirectory: isDirectory, patterns: patterns)
    }

    var isEmpty: Bool { patterns.isEmpty }
}

enum ShareIgnoreFile {
    static let fileName = ".shareignore"

    static func url(in directory: URL) -> URL {
        return directory.appendingPathComponent(fileName)
    }

    static func lines(in directory: URL) -> [String] {
        guard let content = try? String(contentsOf: url(in: directory), encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines)
    }
}
