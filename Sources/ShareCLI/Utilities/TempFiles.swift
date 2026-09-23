import Foundation

/// Tracks temporary artifacts (zips, staged copies, screenshots) created during a run.
///
/// Files handed to a draft (Mail, Messages) must outlive the process, so nothing is
/// deleted automatically at exit. Instead, every run prunes leftovers older than
/// `pruneAge`, and `share clean` removes everything on demand.
enum TempFiles {
    static let pruneAge: TimeInterval = 24 * 60 * 60
    private static var registered: [URL] = []

    static func register(_ url: URL) {
        registered.append(url)
    }

    /// Deletes everything registered in this run. Only safe once the share has fully completed.
    static func removeRegistered() {
        for url in registered {
            try? FileManager.default.removeItem(at: url)
        }
        registered.removeAll()
    }

    /// Removes entries in the scratch directory older than `pruneAge`. Best-effort and quiet.
    static func pruneOld(now: Date = Date()) {
        let dir = Paths.tempDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in entries {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let stamp = values?.contentModificationDate ?? values?.creationDate ?? now
            if now.timeIntervalSince(stamp) > pruneAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
