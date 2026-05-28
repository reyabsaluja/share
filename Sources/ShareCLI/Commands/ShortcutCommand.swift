import ArgumentParser
import Foundation

struct ShortcutCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shortcut",
        abstract: "Run a macOS Shortcut with file input.",
        aliases: ["sc"]
    )

    @Argument(help: "Name of the Shortcut to run.")
    var shortcutName: String?

    @Argument(help: "Files or directories to pass as input. Defaults to current directory.")
    var items: [String] = []

    @Flag(name: .long, help: "List available Shortcuts.")
    var list = false

    @Option(name: .long, help: "Output path for Shortcut result.")
    var output: String?

    @Option(name: .long, help: "Custom archive name (without extension).")
    var name: String?

    @Flag(name: .long, help: "Keep temporary files.")
    var keepTemp = false

    @Flag(name: .long, help: "Show what would happen.")
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

        if list {
            let shortcuts = try ShortcutsBackend.listShortcuts()
            if json {
                let data = try JSONSerialization.data(withJSONObject: shortcuts, options: .prettyPrinted)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                for shortcut in shortcuts {
                    print(shortcut)
                }
            }
            return
        }

        guard let scName = shortcutName else {
            throw ShareError.usage("Provide a shortcut name or use --list")
        }

        let resolved = try InputResolver.resolve(items)
        let prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: keepTemp, verbose: verbose)

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "shortcut", backend: "Shortcuts.app", items: prepared, openedNativeUI: false))
            } else {
                print("Would run shortcut: \(scName)")
                for item in prepared {
                    if case .file(let url) = item.value {
                        print("  input: \(url.path)")
                    }
                }
            }
            return
        }

        if !quiet {
            Log.info("Running shortcut \"\(scName)\"…")
        }

        let backend = ShortcutsBackend(shortcutName: scName, outputPath: output)
        try backend.share(prepared)

        History.record(destination: "shortcut", recipient: scName, items: items.isEmpty ? ["."] : items, archivePath: nil)

        if json {
            print(JSONOutput.success(destination: "shortcut", backend: backend.name, items: prepared, openedNativeUI: false))
        }
    }
}
