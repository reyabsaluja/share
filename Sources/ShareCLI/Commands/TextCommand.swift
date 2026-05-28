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

    @Option(name: [.short, .long], help: "Destination: airdrop, email, messages, copy.")
    var to: String?

    @Option(name: .long, help: "Recipient (for email/messages).")
    var recipient: String?

    @Flag(name: .long, help: "Read from clipboard instead of stdin.")
    var clipboard = false

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

        if dryRun {
            print("Would share text (\(text.count) chars): \(text.prefix(80))")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if !quiet {
            Log.info("Copied to clipboard (\(text.count) chars) ✓")
        }
    }
}
