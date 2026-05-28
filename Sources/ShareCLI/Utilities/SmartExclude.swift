import Foundation

enum SmartExclude {
    static let excludedNames: Set<String> = [
        ".git",
        "node_modules",
        ".DS_Store",
        ".env",
        ".env.local",
        ".env.production",
        ".env.development",
        ".build",
        ".swiftpm",
        "DerivedData",
        "__pycache__",
        ".pytest_cache",
        ".mypy_cache",
        "target",
        "dist",
        ".next",
        ".nuxt",
        "Pods",
        ".gradle",
        "build",
        "venv",
        ".venv",
    ]

    static func stage(directory: URL, verbose: Bool) throws -> URL {
        let fm = FileManager.default
        let stagingDir = Packager.tempDirectory().appendingPathComponent("smart-\(UUID().uuidString)")
        let destDir = stagingDir.appendingPathComponent(directory.lastPathComponent)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let projectType = ProjectDetector.detect(at: directory)
        let projectExcludes = ProjectDetector.excludes(for: projectType)
        let shareIgnorePatterns = ShareIgnore.loadPatterns(from: directory)
        let ignoreSet = Set(shareIgnorePatterns.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
        let allExcludes = excludedNames.union(projectExcludes).union(ignoreSet)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.producesRelativePathURLs]
        ) else {
            throw ShareError.packagingFailed("Cannot enumerate directory")
        }

        var skippedCount = 0

        for case let url as URL in enumerator {
            let components = url.relativePath.split(separator: "/").map(String.init)

            let shouldExclude = components.contains { allExcludes.contains($0) }
            if shouldExclude {
                if url.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                skippedCount += 1
                continue
            }

            let destURL = destDir.appendingPathComponent(url.relativePath)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: destURL)
            }
        }

        if verbose && skippedCount > 0 {
            Log.debug("Excluded \(skippedCount) items with --smart (detected: \(projectType))")
        }

        return destDir
    }
}
