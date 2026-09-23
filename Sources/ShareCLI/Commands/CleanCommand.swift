import ArgumentParser
import Foundation

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove temporary archives, staged copies and screenshots.",
        discussion: "Every run already prunes scratch files older than 24 hours; this removes them on demand."
    )

    @Flag(name: .long, help: "Remove everything, regardless of age.")
    var all = false

    @Option(name: .long, help: "Remove entries older than this many hours (default 24).")
    var olderThan: Int = 24

    @Flag(name: .long, help: "Show what would be removed.")
    var dryRun = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        let tmpDir = Paths.tempDirectory
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: []) else {
            if json { print(JSONOutput.format(["ok": true, "removed": 0, "freedBytes": 0])) } else { print("Nothing to clean.") }
            return
        }

        let cutoff = Date().addingTimeInterval(-Double(max(0, olderThan)) * 3600)
        var totalSize: Int64 = 0
        var removed: [String] = []

        for url in contents {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            let modified = values?.contentModificationDate ?? .distantPast
            guard all || modified < cutoff else { continue }

            let size = values?.isDirectory == true ? DirectoryStats.measure(url).totalBytes : (Packager.fileSize(url) ?? 0)
            if dryRun {
                print("Would remove: \(url.lastPathComponent) " + Color.dim("(\(HumanReadable.fileSize(size)))"))
            } else {
                try? fm.removeItem(at: url)
            }
            totalSize += size
            removed.append(url.lastPathComponent)
        }

        if json {
            print(JSONOutput.format(["ok": true, "dryRun": dryRun, "removed": removed.count, "freedBytes": totalSize, "directory": tmpDir.path] as [String: Any]))
            return
        }
        if removed.isEmpty {
            print("Nothing to clean " + Color.dim("(\(tmpDir.path))"))
        } else if dryRun {
            print("\nWould free " + Color.bold(HumanReadable.fileSize(totalSize)) + " (\(HumanReadable.count(removed.count, "entry", "entries")))")
        } else {
            Log.success("Cleaned \(HumanReadable.fileSize(totalSize)) (\(HumanReadable.count(removed.count, "entry", "entries"))) ✓")
        }
    }
}
