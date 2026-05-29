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
        let nameExcludes = excludedNames.union(projectExcludes)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        ) else {
            throw ShareError.packagingFailed("Cannot enumerate directory")
        }

        let basePath = directory.standardized.path
        var skippedCount = 0

        for case let url as URL in enumerator {
            let fullPath = url.standardized.path
            guard fullPath.count > basePath.count else { continue }
            let relativePath = String(fullPath.dropFirst(basePath.count + 1))
            let components = relativePath.split(separator: "/").map(String.init)

            let excludedByName = components.contains { nameExcludes.contains($0) }
            let excludedByPattern = !shareIgnorePatterns.isEmpty && components.contains { component in
                ShareIgnore.shouldExclude(name: component, patterns: shareIgnorePatterns)
            }
            if excludedByName || excludedByPattern {
                enumerator.skipDescendants()
                skippedCount += 1
                continue
            }

            let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues?.isSymbolicLink == true {
                let resolved = url.resolvingSymlinksInPath().standardized.path
                if !resolved.hasPrefix(basePath + "/") {
                    skippedCount += 1
                    continue
                }
            }

            let destURL = destDir.appendingPathComponent(relativePath)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

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
