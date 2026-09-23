import Foundation

/// A quick, bounded measurement of a directory tree.
struct DirectoryStats {
    var fileCount = 0
    var directoryCount = 0
    var totalBytes: Int64 = 0
    /// True when the walk stopped early because the tree is enormous.
    var truncated = false

    static let defaultFileLimit = 250_000

    /// Walks `directory`, skipping anything `rules` excludes, and stops after `fileLimit` files.
    static func measure(_ directory: URL, rules: ExcludeRules? = nil, fileLimit: Int = defaultFileLimit) -> DirectoryStats {
        var stats = DirectoryStats()
        let base = directory.standardized
        let relativizer = RelativePath(base: base)
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
            options: []
        ) else { return stats }

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
            let relative = relativizer.of(url)
            let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true

            if let rules = rules, rules.isExcluded(relativePath: relative, isDirectory: isDirectory) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            if isDirectory {
                stats.directoryCount += 1
                continue
            }
            stats.fileCount += 1
            stats.totalBytes += Int64(values?.fileSize ?? 0)
            if stats.fileCount >= fileLimit {
                stats.truncated = true
                break
            }
        }
        return stats
    }

    var summary: String {
        let size = HumanReadable.fileSize(totalBytes)
        let files = HumanReadable.count(fileCount, "file")
        return truncated ? "over \(files), \(size)+" : "\(files), \(size)"
    }
}
