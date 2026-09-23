import ArgumentParser
import Foundation

struct PreviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "Show what would be shared: sizes, project type, exclusions, and sensitive files.",
        aliases: ["ls", "info"]
    )

    @Argument(help: "Files, directories, or URLs. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Show what --smart would exclude.")
    var smart = false

    @Option(name: .long, help: "Extra ignore pattern to evaluate. Repeatable.")
    var exclude: [String] = []

    @Flag(name: .long, help: "List every excluded path instead of the first few.")
    var all = false

    func run() throws {
        output.apply()
        let resolved = try InputResolver.resolve(items)
        let useSmart = smart || ShareConfig.current.smart == true

        if output.json {
            print(JSONOutput.format(resolved.map { describe($0, smart: useSmart) }))
            return
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        print("")
        var header = "  " + Color.bold(GitContext.repoName() ?? cwd.lastPathComponent)
        if let branch = GitContext.branchName(), !GitContext.isDefaultBranch(branch) { header += " " + Color.cyan("(\(branch))") }
        let projectType = ProjectDetector.detect()
        if projectType != .unknown { header += " " + Color.dim("[\(projectType.rawValue)]") }
        if GitContext.repoRoot() != nil && GitContext.isDirty() { header += " " + Color.yellow("● uncommitted changes") }
        print(header)
        print("")

        for item in resolved {
            switch item {
            case .file(let url):
                print("  " + Color.green("●") + " \(url.lastPathComponent)  " + Color.dim("(\(HumanReadable.fileSizeAt(url.path) ?? "?"))"))
                if let reason = SecretsDetector.isSensitive(url.lastPathComponent) ? "sensitive file name" : SecretsDetector.scanContents(of: url) {
                    print("     " + Color.yellow("⚠ \(reason)"))
                }

            case .directory(let url):
                let rules = useSmart ? ExcludeRules.smart(for: url, extra: exclude) : (exclude.isEmpty ? nil : ExcludeRules.explicit(for: url, extra: exclude))
                let raw = DirectoryStats.measure(url, fileLimit: 100_000)
                print("  " + Color.cyan("●") + " \(url.lastPathComponent)/  " + Color.dim("(\(raw.summary))"))

                if let rules = rules {
                    let filtered = DirectoryStats.measure(url, rules: rules, fileLimit: 100_000)
                    let plan = SmartExclude.plan(directory: url, rules: rules)
                    print("     " + Color.dim("with \(useSmart ? "--smart" : "--exclude"): \(filtered.summary)"))
                    if !plan.excluded.isEmpty {
                        print("     " + Color.dim("excluded:"))
                        let shown = all ? plan.excluded : Array(plan.excluded.prefix(8))
                        for name in shown { print("       " + Color.red("✕") + " " + Color.dim(name)) }
                        if plan.excluded.count > shown.count { print("       " + Color.dim("… and \(plan.excluded.count - shown.count) more (use --all)")) }
                    }
                    if GitContext.isRepoRoot(url) && (ShareConfig.current.gitignore ?? true) {
                        print("     " + Color.dim(".gitignore is honored (git ls-files)"))
                    }
                }

                let secrets = SecretsDetector.scan(directory: url, rules: rules)
                if !secrets.isEmpty {
                    print("     " + Color.yellow("⚠ sensitive files that would be shared:"))
                    let shown = all ? secrets : Array(secrets.prefix(5))
                    for s in shown { print("       " + Color.yellow("!") + " \(s.path)  " + Color.dim("(\(s.reason))")) }
                    if secrets.count > shown.count { print("       " + Color.dim("… and \(secrets.count - shown.count) more")) }
                }
                let archive = GitContext.archiveName(for: url)
                print("     " + Color.dim("archive: \(archive)-<timestamp>.zip"))

            case .url(let url):
                print("  " + Color.cyan("●") + " \(url.absoluteString)")
            case .text(let text):
                print("  " + Color.green("●") + " \"\(text.prefix(60))\"  " + Color.dim("(\(text.count) chars)"))
            }
        }

        print("")
        if !useSmart && resolved.contains(where: \.isDirectory) {
            Log.hint("add --smart to see what would be excluded, or 'share config set smart true' to make it the default")
        }
    }

    private func describe(_ item: ShareItem, smart: Bool) -> [String: Any] {
        switch item {
        case .file(let url):
            var dict: [String: Any] = ["type": "file", "path": url.path, "name": url.lastPathComponent]
            if let size = Packager.fileSize(url) { dict["sizeBytes"] = size }
            if SecretsDetector.isSensitive(url.lastPathComponent) { dict["sensitive"] = "sensitive file name" }
            else if let reason = SecretsDetector.scanContents(of: url) { dict["sensitive"] = reason }
            return dict
        case .directory(let url):
            let rules = smart ? ExcludeRules.smart(for: url, extra: exclude) : nil
            let stats = DirectoryStats.measure(url, rules: rules, fileLimit: 100_000)
            var dict: [String: Any] = [
                "type": "directory",
                "path": url.path,
                "name": url.lastPathComponent,
                "fileCount": stats.fileCount,
                "sizeBytes": stats.totalBytes,
                "project": ProjectDetector.detect(at: url).rawValue,
                "archiveName": GitContext.archiveName(for: url),
                "sensitive": SecretsDetector.scan(directory: url, rules: rules).map { ["path": $0.path, "reason": $0.reason] },
            ]
            if smart { dict["excluded"] = SmartExclude.plan(directory: url, rules: rules).excluded }
            return dict
        case .url(let url):
            return ["type": "url", "url": url.absoluteString]
        case .text(let text):
            return ["type": "text", "text": String(text.prefix(100)), "length": text.count]
        }
    }
}
