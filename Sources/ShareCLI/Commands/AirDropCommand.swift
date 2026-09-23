import AppKit
import ArgumentParser
import Foundation

struct AirDropCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "airdrop",
        abstract: "Share via AirDrop (opens the native device picker).",
        discussion: """
        Directories are zipped first. Several directories, or directories mixed with files,
        become one bundle. Use --no-zip to send a folder as-is, or --smart to leave out
        dependencies, build output and secrets.
        """,
        aliases: ["ad", "drop"]
    )

    @Argument(help: "Files, directories, or URLs. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Flag(name: .long, help: "Share the clipboard contents (text or image) instead of files.")
    var clipboard = false

    @Option(name: .long, help: "Seconds to wait for the AirDrop panel (default from config, else 300).")
    var timeout: Int?

    func run() throws {
        output.apply()

        let resolved: [ShareItem]
        if clipboard {
            resolved = [try Self.clipboardItem()]
        } else {
            resolved = try InputResolver.resolve(items)
        }

        let options = packaging.prepareOptions(destination: "airdrop", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        if output.dryRun {
            Runner.printDryRun(destination: "airdrop", items: prepared, json: output.json)
            return
        }

        guard AirDropBackend.isAvailable else {
            throw ShareError.backendUnavailable("AirDrop is unavailable on this Mac", hint: "AirDrop needs Wi-Fi and Bluetooth turned on")
        }

        Runner.announcePackaged(prepared)
        Log.info("Opening AirDrop…")

        let backend = AirDropBackend(timeout: timeout.map(TimeInterval.init))
        try backend.share(prepared)

        Runner.finish(
            destination: "airdrop",
            backend: backend.name,
            items: prepared,
            recipient: nil,
            sourceArguments: clipboard ? ["--clipboard"] : items,
            openedNativeUI: true,
            json: output.json,
            successMessage: "Sent via AirDrop ✓"
        )
        TempFiles.removeRegistered()
    }

    /// Turns the clipboard into a shareable file (image) or text item.
    static func clipboardItem() throws -> ShareItem {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let first = urls.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) {
                return isDir.boolValue ? .directory(first) : .file(first)
            }
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            let url = Packager.tempDirectory().appendingPathComponent("clipboard-\(DateSlug.current()).png")
            try png.write(to: url)
            TempFiles.register(url)
            return .file(url)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            if InputResolver.isURL(text.trimmingCharacters(in: .whitespacesAndNewlines)), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .url(url)
            }
            let url = Packager.tempDirectory().appendingPathComponent("clipboard-\(DateSlug.current()).txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            TempFiles.register(url)
            return .file(url)
        }
        throw ShareError.usage("the clipboard is empty")
    }
}
