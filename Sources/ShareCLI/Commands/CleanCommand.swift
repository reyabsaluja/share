import ArgumentParser
import Foundation

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove temporary share files."
    )

    @Flag(name: .long, help: "Remove all temp files regardless of age.")
    var all = false

    @Flag(name: .long, help: "Show what would be removed.")
    var dryRun = false

    func run() throws {
        let tmpDir = Packager.tempDirectory()
        let fm = FileManager.default

        guard fm.fileExists(atPath: tmpDir.path) else {
            print("Nothing to clean.")
            return
        }

        guard let contents = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            print("Nothing to clean.")
            return
        }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        var totalSize: Int64 = 0
        var removedCount = 0

        for url in contents {
            let attrs = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let created = attrs?.creationDate ?? Date.distantPast
            let size = Int64(attrs?.fileSize ?? 0)

            let shouldRemove = all || created < cutoff

            if shouldRemove {
                if dryRun {
                    let sizeStr = HumanReadable.fileSize(size)
                    print("Would remove: \(url.lastPathComponent) (\(sizeStr))")
                } else {
                    try? fm.removeItem(at: url)
                }
                totalSize += size
                removedCount += 1
            }
        }

        if removedCount == 0 {
            print("Nothing to clean " + Color.dim("(temp dir is empty)"))
        } else if dryRun {
            print("\nWould free " + Color.bold(HumanReadable.fileSize(totalSize)) + " (\(removedCount) files)")
        } else {
            Log.success("Cleaned \(HumanReadable.fileSize(totalSize)) (\(removedCount) files) ✓")
        }
    }
}
