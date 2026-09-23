import Foundation

/// Everything a command needs to say about how items should be prepared.
struct PrepareOptions {
    /// Where the items are going: "airdrop", "email", "messages", "zip", "shortcut", "serve", "copy".
    var destination: String
    var smart = false
    var noZip = false
    var archiveName: String?
    var excludePatterns: [String] = []
    var verbose = false
    var quiet = false
    var dryRun = false
    var skipSecretsScan = false

    init(destination: String) {
        self.destination = destination
    }

    /// Smart mode is on when requested explicitly or enabled in config.
    var effectiveSmart: Bool {
        return smart || ShareConfig.current.smart == true
    }
}

/// The one pipeline every sharing command runs: safety checks → smart staging →
/// secrets scan → packaging → destination-specific size warnings.
enum Preparer {
    static let emailLimit: Int64 = 25 * 1024 * 1024
    static let messagesLimit: Int64 = 100 * 1024 * 1024
    static let largeDirectoryBytes: Int64 = 1024 * 1024 * 1024
    static let largeDirectoryFiles = 50_000

    static func prepare(_ items: [ShareItem], options: PrepareOptions) throws -> [PreparedShareItem] {
        try guardDangerousRoots(items)

        let useStaging = options.effectiveSmart || !options.excludePatterns.isEmpty
        let start = Date()

        if options.dryRun {
            return try plan(items, options: options, useStaging: useStaging)
        }

        var effective: [ShareItem] = []
        var archiveName = options.archiveName

        for item in items {
            guard case .directory(let dir) = item else {
                effective.append(item)
                continue
            }

            let rules: ExcludeRules? = useStaging
                ? (options.effectiveSmart
                    ? ExcludeRules.smart(for: dir, extra: options.excludePatterns)
                    : ExcludeRules.explicit(for: dir, extra: options.excludePatterns))
                : nil

            try guardLargeDirectory(dir, rules: rules, quiet: options.quiet)

            if !options.skipSecretsScan {
                guard SecretsDetector.warnIfNeeded(directory: dir, rules: rules, quiet: options.quiet) else {
                    throw ShareError.userCancelled
                }
            }

            if useStaging, let rules = rules {
                if archiveName == nil && items.count == 1 {
                    archiveName = GitContext.archiveName(for: dir)
                }
                let staged = try SmartExclude.stage(directory: dir, rules: rules, verbose: options.verbose)
                if !options.quiet && staged.skippedEntries > 0 {
                    Log.info(Color.dim("smart: excluded \(HumanReadable.count(staged.skippedEntries, "entry", "entries"))"))
                }
                effective.append(.directory(staged.url))
            } else {
                effective.append(item)
            }
        }

        let prepared: [PreparedShareItem]
        if options.noZip {
            prepared = effective.map { $0.toPrepared() }
        } else {
            prepared = try Packager.packageIfNeeded(items: effective, archiveName: archiveName, verbose: options.verbose)
        }

        if options.verbose {
            Log.debug("prepared \(HumanReadable.count(prepared.count, "item")) in \(HumanReadable.duration(Date().timeIntervalSince(start)))")
        }

        try checkDestinationLimits(prepared, options: options)
        return prepared
    }

    // MARK: - Dry run

    /// Describes what `prepare` would do, without copying or zipping anything.
    private static func plan(_ items: [ShareItem], options: PrepareOptions, useStaging: Bool) throws -> [PreparedShareItem] {
        var prepared: [PreparedShareItem] = []
        var directories: [(URL, Int64)] = []
        var loose: [PreparedShareItem] = []

        for item in items {
            switch item {
            case .directory(let dir):
                let rules = useStaging ? ExcludeRules.smart(for: dir, extra: options.excludePatterns) : nil
                let stats = DirectoryStats.measure(dir, rules: rules, fileLimit: 20_000)
                directories.append((dir, stats.totalBytes))
                if !options.skipSecretsScan && !options.quiet {
                    let findings = SecretsDetector.scan(directory: dir, rules: rules)
                    if !findings.isEmpty {
                        let names = findings.prefix(5).map(\.path).joined(separator: ", ")
                        let more = findings.count > 5 ? " and \(findings.count - 5) more" : ""
                        Log.warn("\(dir.lastPathComponent) has \(HumanReadable.count(findings.count, "sensitive file")) that would prompt: \(names)\(more)")
                    }
                }
            case .file, .url, .text:
                let p = item.toPrepared()
                if p.kind == .file { loose.append(p) } else { prepared.append(p) }
            }
        }

        if options.noZip {
            prepared.append(contentsOf: loose)
            for (dir, bytes) in directories {
                prepared.append(PreparedShareItem(kind: .file, originalDescription: dir.path, value: .file(dir), packaged: false, temporary: false, sizeBytes: bytes))
            }
            return prepared
        }

        if directories.count == 1 && loose.isEmpty {
            let (dir, bytes) = directories[0]
            let name = options.archiveName ?? GitContext.archiveName(for: dir)
            prepared.append(PreparedShareItem(kind: .file, originalDescription: dir.path, value: .file(Packager.plannedArchiveURL(name: name)), packaged: true, temporary: true, sizeBytes: bytes))
        } else if !directories.isEmpty {
            let name = options.archiveName ?? Packager.bundleName
            let bytes = directories.reduce(0) { $0 + $1.1 } + loose.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
            prepared.append(PreparedShareItem(kind: .file, originalDescription: "bundle", value: .file(Packager.plannedArchiveURL(name: name)), packaged: true, temporary: true, sizeBytes: bytes))
        } else {
            prepared.append(contentsOf: loose)
        }
        return prepared
    }

    // MARK: - Safety checks

    /// Refuses to package the filesystem root or the home directory by accident.
    static func guardDangerousRoots(_ items: [ShareItem]) throws {
        for case .directory(let dir) in items {
            let path = dir.standardized.path
            if path == "/" || path == "/Users" || path == "/Volumes" || path == "/System" || path == "/private" {
                throw ShareError.refused("refusing to package \(path)")
            }
            if path == Paths.home.path && !Prompt.assumeYes {
                throw ShareError.refused(
                    "refusing to package your entire home directory",
                    hint: "cd into a project first, or pass --yes if you really mean it"
                )
            }
        }
    }

    /// Warns (and asks) before copying or zipping something enormous.
    static func guardLargeDirectory(_ dir: URL, rules: ExcludeRules?, quiet: Bool) throws {
        let stats = DirectoryStats.measure(dir, rules: rules, fileLimit: largeDirectoryFiles)
        guard stats.truncated || stats.totalBytes > largeDirectoryBytes else { return }

        if !quiet {
            Log.warn("\(dir.lastPathComponent) is large (\(stats.summary))")
            if rules == nil { Log.hint("use --smart to skip build output and dependencies") }
        }
        if Prompt.assumeYes { return }
        guard let answer = Prompt.confirm("Package it anyway?") else {
            throw ShareError.refused("directory too large for non-interactive mode", hint: "pass --yes to package it regardless")
        }
        guard answer else { throw ShareError.userCancelled }
    }

    /// Email and Messages have practical attachment limits; warn before creating a draft that will bounce.
    static func checkDestinationLimits(_ items: [PreparedShareItem], options: PrepareOptions) throws {
        let total = items.compactMap(\.sizeBytes).reduce(0, +)
        switch options.destination {
        case "email" where total > emailLimit:
            if !options.quiet {
                Log.warn("total size \(HumanReadable.fileSize(total)) exceeds the usual 25 MB email attachment limit")
                Log.hint("consider 'share airdrop', 'share serve', or 'share zip --output' instead")
            }
            if Prompt.assumeYes { return }
            guard let answer = Prompt.confirm("Draft it anyway?") else {
                throw ShareError.refused("attachments too large for non-interactive mode", hint: "pass --yes to draft it regardless")
            }
            guard answer else { throw ShareError.userCancelled }
        case "messages" where total > messagesLimit:
            if !options.quiet {
                Log.warn("total size \(HumanReadable.fileSize(total)) exceeds the usual 100 MB iMessage limit")
            }
        default:
            if total > 100 * 1024 * 1024 && !options.quiet {
                Log.info(Color.dim("sharing \(HumanReadable.fileSize(total)); this may take a moment"))
            }
        }
    }
}
