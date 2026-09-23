import Foundation

/// Computes paths relative to a base directory, tolerating the `/var` → `/private/var`
/// symlink dance that makes naive prefix matching fail on macOS.
struct RelativePath {
    private let prefixes: [String]

    init(base: URL) {
        var candidates = [base.standardized.path, base.resolvingSymlinksInPath().standardized.path]
        candidates = Array(Set(candidates)).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        prefixes = candidates.sorted { $0.count > $1.count }
    }

    /// The path of `url` relative to the base, or its last component when it lives elsewhere.
    func of(_ url: URL) -> String {
        let candidates = [url.standardized.path, url.resolvingSymlinksInPath().standardized.path]
        for full in candidates {
            for prefix in prefixes where full.hasPrefix(prefix) {
                return String(full.dropFirst(prefix.count))
            }
        }
        return url.lastPathComponent
    }
}
