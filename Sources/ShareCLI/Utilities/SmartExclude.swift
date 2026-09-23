import Foundation

/// Result of staging a directory copy with exclusions applied.
struct StagedDirectory {
    let url: URL
    let copiedFiles: Int
    let skippedEntries: Int
    let projectType: ProjectType
    let usedGit: Bool
}

/// Builds a filtered copy of a directory in the scratch area so it can be zipped or shared
/// without build output, dependencies, VCS metadata or secrets.
enum SmartExclude {
    /// Legacy list kept for tooling that inspects it; the real rules live in `ExcludeRules`.
    static let excludedNames: Set<String> = Set(ExcludeRules.alwaysExcluded.filter { !$0.hasPrefix("!") && !$0.contains("*") })

    static func stage(directory: URL, rules: ExcludeRules? = nil, useGit: Bool? = nil, verbose: Bool) throws -> StagedDirectory {
        let fm = FileManager.default
        let source = directory.standardized
        let stagingRoot = Packager.tempDirectory().appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        let destination = stagingRoot.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        TempFiles.register(stagingRoot)

        let projectType = ProjectDetector.detect(at: source)
        let effectiveRules = rules ?? ExcludeRules.smart(for: source, projectType: projectType)
        let gitEnabled = useGit ?? (ShareConfig.current.gitignore ?? true)

        var copied = 0
        var skipped = 0
        var usedGit = false

        if gitEnabled, let files = GitContext.projectFiles(in: source) {
            usedGit = true
            for relative in files {
                let sourceURL = source.appendingPathComponent(relative)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else { continue }
                if effectiveRules.isExcluded(relativePath: relative, isDirectory: isDir.boolValue) {
                    skipped += 1
                    continue
                }
                if isDir.boolValue {
                    // Submodule or nested repo: walk it with the same rules.
                    let nested = try copyTree(from: sourceURL, to: destination.appendingPathComponent(relative), base: source, rules: effectiveRules)
                    copied += nested.copied
                    skipped += nested.skipped
                } else {
                    try copyFile(from: sourceURL, to: destination.appendingPathComponent(relative))
                    copied += 1
                }
            }
        } else {
            let result = try copyTree(from: source, to: destination, base: source, rules: effectiveRules)
            copied = result.copied
            skipped = result.skipped
        }

        if verbose {
            let how = usedGit ? "git ls-files + rules" : "rules"
            Log.debug("smart: copied \(copied) files, excluded \(skipped) entries (\(projectType), \(how))")
        }

        return StagedDirectory(url: destination, copiedFiles: copied, skippedEntries: skipped, projectType: projectType, usedGit: usedGit)
    }

    /// Counts what staging would do, without copying anything. Used by `preview` and dry runs.
    static func plan(directory: URL, rules: ExcludeRules? = nil) -> (included: Int, excluded: [String]) {
        let source = directory.standardized
        let effectiveRules = rules ?? ExcludeRules.smart(for: source)
        var included = 0
        var excluded: [String] = []
        let relativizer = RelativePath(base: source)
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return (0, [])
        }
        while let url = enumerator.nextObject() as? URL {
            let relative = relativizer.of(url)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if effectiveRules.isExcluded(relativePath: relative, isDirectory: isDir) {
                excluded.append(relative)
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if !isDir { included += 1 }
        }
        return (included, excluded)
    }

    // MARK: - Copy helpers

    private static func copyTree(from source: URL, to destination: URL, base: URL, rules: ExcludeRules) throws -> (copied: Int, skipped: Int) {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw ShareError.packagingFailed("cannot enumerate \(source.path)")
        }

        var copied = 0
        var skipped = 0
        let basePath = base.resolvingSymlinksInPath().standardized.path
        let baseRelativizer = RelativePath(base: base)
        let sourceRelativizer = RelativePath(base: source)

        while let url = enumerator.nextObject() as? URL {
            let relativeToBase = baseRelativizer.of(url)
            let relativeToSource = sourceRelativizer.of(url)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isSymlink = values?.isSymbolicLink == true
            let isDir = values?.isDirectory == true && !isSymlink

            if rules.isExcluded(relativePath: relativeToBase, isDirectory: isDir) {
                if isDir { enumerator.skipDescendants() }
                skipped += 1
                continue
            }

            if isSymlink {
                let resolved = url.resolvingSymlinksInPath().standardized.path
                guard resolved.hasPrefix(basePath + "/") else {
                    skipped += 1
                    continue
                }
            }

            let target = destination.appendingPathComponent(relativeToSource)
            if isDir {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try copyFile(from: url, to: target)
                copied += 1
            }
        }
        return (copied, skipped)
    }

    private static func copyFile(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: source, to: destination)
    }
}
