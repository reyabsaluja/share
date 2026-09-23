import ArgumentParser
import Foundation

struct ShortcutCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shortcut",
        abstract: "Run a macOS Shortcut with the items as input.",
        discussion: "Files are passed with the shortcut's file input; URLs and text are piped on stdin.",
        aliases: ["sc"]
    )

    @Argument(help: "Name of the Shortcut to run.")
    var shortcutName: String?

    @Argument(help: "Files, directories, URLs or text. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Flag(name: [.short, .long], help: "List available Shortcuts.")
    var list = false

    @Option(name: [.short, .long], help: "Write the Shortcut's output to this path.")
    var outputPath: String?

    func run() throws {
        output.apply()

        if list {
            let shortcuts = try ShortcutsBackend.listShortcuts()
            if output.json {
                print(JSONOutput.format(shortcuts))
            } else {
                shortcuts.forEach { print($0) }
            }
            return
        }

        guard let scName = shortcutName else {
            throw ShareError.usage("provide a shortcut name, or --list to see them")
        }

        let resolved = try InputResolver.resolve(items)
        let options = packaging.prepareOptions(destination: "shortcut", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        if output.dryRun {
            Runner.printDryRun(destination: "run shortcut", recipient: scName, items: prepared, json: output.json)
            return
        }

        Runner.announcePackaged(prepared)
        Log.info("Running shortcut \"\(scName)\"…")

        let backend = ShortcutsBackend(shortcutName: scName, outputPath: outputPath)
        try backend.share(prepared)

        Runner.finish(
            destination: "shortcut",
            backend: backend.name,
            items: prepared,
            recipient: scName,
            sourceArguments: items,
            openedNativeUI: false,
            json: output.json,
            successMessage: "Shortcut \"\(scName)\" finished ✓"
        )
    }
}
