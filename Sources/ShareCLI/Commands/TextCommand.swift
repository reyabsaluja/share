import AppKit
import ArgumentParser
import Foundation

struct TextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Share a snippet of text: from arguments, stdin, or the clipboard.",
        discussion: "With --to it goes out via email or Messages; otherwise it is copied to the clipboard.",
        aliases: ["txt"]
    )

    @Argument(help: "Text to share. If omitted, reads stdin (or the clipboard with --clipboard).")
    var words: [String] = []

    @OptionGroup var output: OutputOptions

    @Option(name: [.short, .long], help: "Recipient: email, phone, or @alias.", completion: .custom(Completions.aliasNames))
    var to: String?

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Flag(name: .long, help: "Read the text from the clipboard.")
    var clipboard = false

    @Flag(name: .long, help: "Send immediately instead of opening a draft.")
    var send = false

    func run() throws {
        output.apply()

        let text: String
        if !words.isEmpty {
            text = words.joined(separator: " ")
        } else if clipboard {
            guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else {
                throw ShareError.usage("the clipboard has no text")
            }
            text = content
        } else if let piped = StdinReader.readIfPiped() {
            text = piped
        } else {
            throw ShareError.usage("provide text as arguments, pipe it on stdin, or use --clipboard")
        }

        let item = PreparedShareItem(kind: .text, originalDescription: String(text.prefix(50)), value: .text(text), packaged: false, temporary: false, sizeBytes: Int64(text.utf8.count))

        guard let recipient = to else {
            if output.dryRun {
                Runner.printDryRun(destination: "copy to clipboard", items: [item], json: output.json)
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if output.json {
                print(JSONOutput.format(["ok": true, "destination": "clipboard", "characters": text.count]))
            } else {
                Log.success("Copied \(text.count) characters to clipboard ✓")
            }
            return
        }

        let destinations = try Runner.destinations(for: recipient)
        for destination in destinations {
            switch destination {
            case .email(let address):
                let effectiveSubject = subject ?? "Shared text"
                if output.dryRun {
                    Runner.printDryRun(destination: "email", recipient: address, items: [item], json: output.json, details: [("subject", effectiveSubject), ("action", send ? "send" : "draft")])
                    continue
                }
                Log.info(send ? "Sending to \(address)…" : "Drafting to \(address)…")
                let backend = MailBackend(options: MailOptions(to: address, subject: effectiveSubject, body: text, send: send))
                try backend.share([])
                Runner.finish(destination: "text", backend: backend.name, items: [item], recipient: address, sourceArguments: [], openedNativeUI: !send, json: output.json)

            case .messages(let handle):
                if output.dryRun {
                    Runner.printDryRun(destination: "messages", recipient: handle, items: [item], json: output.json, details: [("action", send ? "send" : "draft")])
                    continue
                }
                Log.info(send ? "Sending to \(handle)…" : "Opening Messages for \(handle)…")
                let backend = MessagesBackend(options: MessagesOptions(recipient: handle, text: text, send: send))
                try backend.share([])
                Runner.finish(destination: "text", backend: backend.name, items: [item], recipient: handle, sourceArguments: [], openedNativeUI: !send, json: output.json, successMessage: send ? "Sent ✓" : nil)

            case .airdrop:
                let url = Packager.tempDirectory().appendingPathComponent("text-\(DateSlug.current()).txt")
                try text.write(to: url, atomically: true, encoding: .utf8)
                let fileItem = ShareItem.file(url).toPrepared()
                if output.dryRun {
                    Runner.printDryRun(destination: "airdrop", items: [fileItem], json: output.json)
                    continue
                }
                Log.info("Opening AirDrop…")
                let backend = AirDropBackend()
                try backend.share([fileItem])
                Runner.finish(destination: "text", backend: backend.name, items: [fileItem], recipient: nil, sourceArguments: [], openedNativeUI: true, json: output.json)
            }
        }
    }
}
