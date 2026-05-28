import ArgumentParser
import AppKit
import Foundation

struct ZipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zip",
        abstract: "Package files/folders into a zip archive."
    )

    @Argument(help: "Files or directories to package. Defaults to current directory.")
    var items: [String] = []

    @Option(name: [.short, .long], help: "Custom archive name (without extension).")
    var name: String?

    @Option(name: .shortAndLong, help: "Output path for the zip file.")
    var output: String?

    @Flag(name: .long, help: "Exclude .git, node_modules, .DS_Store, .env, build caches.")
    var smart = false

    @Flag(name: .long, help: "Don't copy archive path to clipboard.")
    var noCopy = false

    @Flag(name: .long, help: "Show what would happen without creating the archive.")
    var dryRun = false

    @Flag(name: .long, help: "Print verbose output.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    @Flag(name: .long, help: "Output result as JSON.")
    var json = false

    func run() throws {
        Log.verbose = verbose
        Log.quiet = quiet

        let resolved = try InputResolver.resolve(items)

        if dryRun {
            let archiveName = name ?? defaultName(for: resolved)
            let slug = DateSlug.current()
            let outputName: String
            if let out = output {
                outputName = out
            } else {
                outputName = Packager.tempDirectory().appendingPathComponent("\(archiveName)-\(slug).zip").path
            }

            if json {
                let result: [String: Any] = [
                    "ok": true,
                    "destination": "zip",
                    "outputPath": outputName,
                    "dryRun": true,
                ]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                for item in resolved {
                    switch item {
                    case .file(let url): print("Would package: \(url.path)")
                    case .directory(let url): print("Would package: \(url.path)")
                    case .url(let url): print("Would skip:    \(url.absoluteString) (not a file)")
                    case .text: print("Would skip:    (text input)")
                    }
                }
                print("Would create:  \(outputName)")
            }
            return
        }

        let effectiveItems: [ShareItem]
        if smart {
            effectiveItems = try resolved.map { item -> ShareItem in
                if case .directory(let url) = item {
                    let cleaned = try SmartExclude.stage(directory: url, verbose: verbose)
                    return .directory(cleaned)
                }
                return item
            }
        } else {
            effectiveItems = resolved
        }

        let zipURL = try Packager.zipOnly(items: effectiveItems, archiveName: name, outputPath: output, verbose: verbose)

        if !noCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(zipURL.path, forType: .string)
        }

        History.record(destination: "zip", recipient: nil, items: items.isEmpty ? ["."] : items, archivePath: zipURL.path)

        if json {
            let size = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64) ?? 0
            let result: [String: Any] = [
                "ok": true,
                "destination": "zip",
                "outputPath": zipURL.path,
                "sizeBytes": size as Any,
                "copiedToClipboard": !noCopy,
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            let size = HumanReadable.fileSizeAt(zipURL.path) ?? ""
            print("\(zipURL.path) " + Color.dim("(\(size))"))
            if !noCopy && !quiet {
                Log.success("Copied to clipboard ✓")
            }
        }
    }

    private func defaultName(for items: [ShareItem]) -> String {
        if items.count == 1 {
            switch items[0] {
            case .file(let url): return url.deletingPathExtension().lastPathComponent
            case .directory(let url): return url.lastPathComponent
            default: return "share-bundle"
            }
        }
        return "share-bundle"
    }
}
