import AppKit
import ArgumentParser
import Foundation

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot and share it.",
        discussion: "Without a recipient the image is copied to the clipboard. Pass an email, phone number, @alias, or 'airdrop' to send it directly. --selection and --window use the interactive picker.",
        aliases: ["ss", "snap"]
    )

    @Argument(help: "Recipient (email, phone, @alias) or 'airdrop'. Omit to copy to the clipboard.", completion: .custom(Completions.aliasNames))
    var recipient: String?

    @OptionGroup var output: OutputOptions

    @Flag(name: [.short, .long], help: "Capture a selection instead of the full screen.")
    var selection = false

    @Flag(name: [.short, .long], help: "Capture a single window.")
    var window = false

    @Option(name: [.short, .long], help: "Seconds to wait before capturing.")
    var delay: Int?

    @Option(name: .long, help: "Also save the screenshot to this path.")
    var save: String?

    @Flag(name: .long, help: "Keep the temporary screenshot file after sharing.")
    var keep = false

    @Flag(name: .long, help: "Send immediately instead of opening a draft.")
    var send = false

    @Option(name: .long, help: "Email subject.")
    var subject: String?

    func run() throws {
        output.apply()

        let stamp = DateSlug.current()
        let tmpPath = Packager.tempDirectory().appendingPathComponent("screenshot-\(stamp).png")

        let destinations: [Destination]? = try recipient.map { try Runner.destinations(for: $0) }

        if output.dryRun {
            let mode = selection ? "selection" : (window ? "window" : "full screen")
            let target = destinations?.map { $0.recipient ?? $0.name }.joined(separator: ", ") ?? "clipboard"
            Swift.print("Would capture \(mode) → \(tmpPath.lastPathComponent) and share to \(target)")
            return
        }

        var args: [String] = ["-x"]  // no shutter sound; matches "quiet CLI" expectations
        if selection { args.append("-i") } else if window { args.append("-iW") }
        if let d = delay, d > 0 { args.append(contentsOf: ["-T", "\(d)"]) }
        args.append(tmpPath.path)

        Log.info(selection || window ? "Select what to capture… (Esc to cancel)" : "Capturing…")

        let result = Subprocess.run("/usr/sbin/screencapture", arguments: args)
        guard result.status == 0, FileManager.default.fileExists(atPath: tmpPath.path) else {
            if result.stderr.lowercased().contains("not permitted") || result.stderr.lowercased().contains("screen recording") {
                throw ShareError.automationDenied(app: "Screen Recording")
            }
            throw ShareError.userCancelled
        }
        if !keep { TempFiles.register(tmpPath) }

        if let savePath = save {
            let url = InputResolver.expandPath(savePath)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: tmpPath, to: url)
            Log.info("Saved → \(url.path)")
        }

        Log.info("Captured " + Color.dim("(\(HumanReadable.fileSizeAt(tmpPath.path) ?? "?"))"))
        let item = ShareItem.file(tmpPath).toPrepared()

        guard let destinations = destinations else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let image = NSImage(contentsOf: tmpPath) {
                pasteboard.writeObjects([image])
            }
            Log.success("Copied to clipboard ✓")
            if output.json { Swift.print(JSONOutput.format(["ok": true, "destination": "clipboard", "path": tmpPath.path])) }
            if !keep { try? FileManager.default.removeItem(at: tmpPath) }
            return
        }

        for destination in destinations {
            switch destination {
            case .email(let address):
                Log.info(send ? "Sending to \(address)…" : "Drafting to \(address)…")
                let backend = MailBackend(options: MailOptions(to: address, subject: subject ?? "Screenshot \(stamp)", send: send))
                try backend.share([item])
                Runner.finish(destination: "screenshot", backend: backend.name, items: [item], recipient: address, sourceArguments: [], openedNativeUI: !send, json: output.json)
            case .messages(let handle):
                Log.info(send ? "Sending to \(handle)…" : "Opening Messages for \(handle)…")
                let backend = MessagesBackend(options: MessagesOptions(recipient: handle, text: nil, send: send))
                try backend.share([item])
                Runner.finish(destination: "screenshot", backend: backend.name, items: [item], recipient: handle, sourceArguments: [], openedNativeUI: !send, json: output.json)
            case .airdrop:
                Log.info("Opening AirDrop…")
                let backend = AirDropBackend()
                try backend.share([item])
                Runner.finish(destination: "screenshot", backend: backend.name, items: [item], recipient: nil, sourceArguments: [], openedNativeUI: true, json: output.json, successMessage: "Sent via AirDrop ✓")
            }
        }
    }
}
