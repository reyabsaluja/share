import AppKit
import ArgumentParser
import Foundation

struct ZipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zip",
        abstract: "Package files and folders into a zip archive.",
        discussion: """
        Without --output the archive goes to the scratch directory and its path is copied
        to the clipboard. --output may be a file path or an existing directory.
        """
    )

    @Argument(help: "Files or directories to package. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions

    @Option(name: [.short, .long], help: "Archive name, without the .zip extension.")
    var name: String?

    @Option(name: [.short, .long], help: "Output file path, or a directory to place the archive in.")
    var outputPath: String?

    @Flag(name: .long, help: "Exclude VCS metadata, dependencies, build output and secrets.")
    var smart = false

    @Option(name: .long, help: "Extra ignore pattern, gitignore style. Repeatable.")
    var exclude: [String] = []

    @Flag(name: .long, help: "Overwrite the output file if it exists.")
    var force = false

    @Flag(name: .long, help: "Do not copy the archive path to the clipboard.")
    var noCopy = false

    func run() throws {
        output.apply()

        let resolved = try InputResolver.resolve(items)
        guard resolved.contains(where: { if case .file = $0 { return true }; if case .directory = $0 { return true }; return false }) else {
            throw ShareError.usage("nothing to zip: provide at least one file or directory")
        }

        var options = PrepareOptions(destination: "zip")
        options.smart = smart
        options.excludePatterns = exclude
        options.noZip = true  // we call zipOnly ourselves to control the output path
        options.verbose = output.verbose
        options.quiet = output.quiet
        options.dryRun = output.dryRun
        options.archiveName = name

        let archiveName = name ?? Packager.defaultArchiveName(for: resolved)
        // Validate the destination before doing any work so a clobber is refused up front.
        let plannedOutput = try Packager.resolveOutput(outputPath, name: archiveName, overwrite: force)

        if output.dryRun {
            let prepared = try Preparer.prepare(resolved, options: options)
            Runner.printDryRun(destination: "zip", items: prepared, json: output.json, details: [("output", plannedOutput.path)])
            return
        }

        // Preparer handles safety checks, secrets and smart staging; packaging happens below.
        let staged = try Preparer.prepare(resolved, options: options)
        let stagedItems: [ShareItem] = staged.compactMap { item in
            guard let url = item.fileURL else { return nil }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? .directory(url) : .file(url)
        }

        let zipURL = try Packager.zipOnly(items: stagedItems, archiveName: archiveName, outputPath: plannedOutput.path, overwrite: force, verbose: output.verbose)

        let shouldCopy = !noCopy && (ShareConfig.current.copyZip ?? true)
        if shouldCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(zipURL.path, forType: .string)
        }

        History.record(destination: "zip", recipient: nil, items: items.isEmpty ? ["."] : items, archivePath: zipURL.path)

        let size = Packager.fileSize(zipURL) ?? 0
        if output.json {
            print(JSONOutput.format([
                "ok": true,
                "destination": "zip",
                "outputPath": zipURL.path,
                "sizeBytes": size,
                "copiedToClipboard": shouldCopy,
            ] as [String: Any]))
        } else {
            print(zipURL.path)
            fflush(stdout)
            Log.info(Color.dim("(\(HumanReadable.fileSize(size)))") + (shouldCopy ? Color.green("  path copied to clipboard ✓") : ""))
        }
        Notifier.sendIfEnabled(message: "Created \(zipURL.lastPathComponent)")
    }
}
