import ArgumentParser
import AppKit
import Foundation

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy a file path or URL to clipboard."
    )

    @Argument(help: "Files or directories to copy path of. Defaults to current directory.")
    var items: [String] = []

    @Flag(name: .long, help: "Package into zip first, then copy archive path.")
    var zip = false

    @Flag(name: .long, help: "Copy the absolute POSIX path.")
    var path = false

    @Flag(name: .long, help: "Copy as file:// URL.")
    var fileURL = false

    @Option(name: .long, help: "Custom archive name (without extension).")
    var name: String?

    @Flag(name: .long, help: "Print verbose output.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.verbose = verbose
        Log.quiet = quiet

        let resolved = try InputResolver.resolve(items)

        let pathToCopy: String

        if zip {
            let zipURL = try Packager.zipOnly(items: resolved, archiveName: name, outputPath: nil, verbose: verbose)
            if fileURL {
                pathToCopy = zipURL.absoluteString
            } else {
                pathToCopy = zipURL.path
            }
        } else {
            guard let first = resolved.first else {
                throw ShareError.usage("Nothing to copy")
            }

            switch first {
            case .file(let url), .directory(let url):
                if fileURL {
                    pathToCopy = url.absoluteString
                } else {
                    pathToCopy = url.path
                }
            case .url(let url):
                pathToCopy = url.absoluteString
            case .text(let text):
                pathToCopy = text
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pathToCopy, forType: .string)

        if !quiet {
            Log.success("Copied ✓")
            fputs("  " + pathToCopy + "\n", stderr)
        }
    }
}
