import ArgumentParser
import AppKit
import Foundation

struct TextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Share text via any destination. Reads from args, stdin, or clipboard.",
        aliases: ["txt"]
    )

    @Argument(help: "Text to share. If omitted, reads from stdin or clipboard.")
    var words: [String] = []

    @Option(name: [.short, .long], help: "Recipient (email, phone, or @alias). If omitted, copies to clipboard.")
    var to: String?

    @Flag(name: .long, help: "Read from clipboard instead of stdin.")
    var clipboard = false

    @Flag(name: .long, help: "Send immediately (for messages).")
    var send = false

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.quiet = quiet

        let text: String
        if !words.isEmpty {
            text = words.joined(separator: " ")
        } else if clipboard {
            guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else {
                throw ShareError.usage("Clipboard is empty")
            }
            text = content
        } else if let piped = StdinReader.readIfPiped() {
            text = piped
        } else {
            throw ShareError.usage("Provide text as arguments, pipe from stdin, or use --clipboard")
        }

        if let recipient = to {
            let resolved = Aliases.resolve(recipient) ?? recipient

            if dryRun {
                let dest = SmartRouter.detect(resolved)
                let destName: String
                switch dest {
                case .email: destName = "email"
                case .messages: destName = "messages"
                case .airdrop, .none: destName = "clipboard"
                }
                print("Would share via \(destName) to \(resolved)")
                print("  text: \(text.prefix(80))")
                return
            }

            if let destination = SmartRouter.detect(resolved) {
                switch destination {
                case .email(let address):
                    if !quiet { Log.info("Drafting to \(address)…") }
                    let options = MailOptions(to: address, subject: "Shared text", body: text, send: false)
                    let backend = MailBackend(options: options)
                    try backend.share([])

                case .messages(let phone):
                    if !quiet {
                        if send { Log.info("Sending to \(phone)…") }
                        else { Log.info("Opening Messages to \(phone)…") }
                    }
                    let options = MessagesOptions(recipient: phone, text: text, send: send)
                    let backend = MessagesBackend(options: options)
                    try backend.share([])

                case .airdrop:
                    break
                }
                return
            }
        }

        if dryRun {
            print("Would copy to clipboard (\(text.count) chars): \(text.prefix(80))")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if !quiet {
            Log.success("Copied to clipboard (\(text.count) chars) ✓")
        }
    }
}
