import AppKit
import ArgumentParser
import Foundation

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy a path, URL, file contents, or a fresh zip to the clipboard.",
        aliases: ["cp", "clip"]
    )

    @Argument(help: "File, directory, or URL. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Zip first, then copy the archive path.")
    var zip = false

    @Flag(name: .long, help: "Copy as a file:// URL.")
    var fileURL = false

    @Flag(name: .long, help: "Copy the file itself (paste into Finder, Mail, Slack…) instead of its path.")
    var file = false

    @Flag(name: .long, help: "Copy the file's text contents.")
    var contents = false

    @Flag(name: .long, help: "Exclude VCS metadata, dependencies, build output and secrets when zipping.")
    var smart = false

    @Option(name: [.short, .long], help: "Archive name when zipping.")
    var name: String?

    func run() throws {
        output.apply()
        let resolved = try InputResolver.resolve(items)
        guard let first = resolved.first else { throw ShareError.usage("nothing to copy") }

        let pasteboard = NSPasteboard.general

        if zip {
            var options = PrepareOptions(destination: "copy")
            options.smart = smart
            options.archiveName = name
            options.verbose = output.verbose
            options.quiet = output.quiet
            let prepared = try Preparer.prepare(resolved, options: options)
            guard let url = prepared.first(where: \.packaged)?.fileURL ?? prepared.first?.fileURL else {
                throw ShareError.usage("nothing to zip")
            }
            let text = fileURL ? url.absoluteString : url.path
            if output.dryRun { print("Would copy: \(text)"); return }
            pasteboard.clearContents()
            if file {
                pasteboard.writeObjects([url as NSURL])
            } else {
                pasteboard.setString(text, forType: .string)
            }
            report(file ? url.lastPathComponent : text)
            return
        }

        switch first {
        case .file(let url), .directory(let url):
            if contents {
                guard case .file = first, let text = try? String(contentsOf: url, encoding: .utf8) else {
                    throw ShareError.unsupported("--contents needs a UTF-8 text file")
                }
                if output.dryRun { print("Would copy \(text.count) characters from \(url.lastPathComponent)"); return }
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                report("\(text.count) characters from \(url.lastPathComponent)")
            } else if file {
                if output.dryRun { print("Would copy file: \(url.path)"); return }
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
                report(url.lastPathComponent)
            } else {
                let text = fileURL ? url.absoluteString : url.path
                if output.dryRun { print("Would copy: \(text)"); return }
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                report(text)
            }
        case .url(let url):
            if output.dryRun { print("Would copy: \(url.absoluteString)"); return }
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
            report(url.absoluteString)
        case .text(let text):
            if output.dryRun { print("Would copy \(text.count) characters"); return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            report("\(text.count) characters")
        }
    }

    private func report(_ what: String) {
        if output.json {
            print(JSONOutput.format(["ok": true, "destination": "clipboard", "copied": what]))
        } else {
            Log.success("Copied ✓ " + Color.dim(what))
        }
    }
}
