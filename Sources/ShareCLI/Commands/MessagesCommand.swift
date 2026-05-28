import ArgumentParser
import Foundation

struct MessagesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "messages",
        abstract: "Share via Messages.",
        aliases: ["message", "msg", "im", "sms"]
    )

    @Argument(help: "Recipient phone number or email.")
    var recipient: String

    @Argument(help: "Text, files, or URLs. Non-file args become the message body.")
    var items: [String] = []

    @Option(name: [.short, .long], help: "Message text (alternative to positional).")
    var text: String?

    @Option(name: [.short, .long], help: "Archive name.")
    var name: String?

    @Flag(name: .long, help: "Send immediately instead of composing a draft.")
    var send = false

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Print verbose output.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        Log.verbose = verbose
        Log.quiet = quiet

        let resolvedRecipient = Aliases.resolve(recipient) ?? recipient
        let shouldSend = send

        var textParts: [String] = []
        var fileParts: [String] = []

        for item in items {
            if InputResolver.isURL(item) {
                textParts.append(item)
            } else {
                let expanded = NSString(string: item).expandingTildeInPath
                let resolved: URL
                if expanded.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: expanded)
                } else {
                    resolved = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent(expanded)
                }
                if FileManager.default.fileExists(atPath: resolved.standardized.path) {
                    fileParts.append(item)
                } else {
                    textParts.append(item)
                }
            }
        }

        let stdinText = StdinReader.readIfPiped()

        let messageText: String
        if let explicit = text {
            messageText = explicit
        } else if !textParts.isEmpty {
            messageText = textParts.joined(separator: " ")
        } else if let piped = stdinText {
            messageText = piped
        } else {
            messageText = ""
        }

        let resolved: [ShareItem]
        if fileParts.isEmpty && messageText.isEmpty {
            resolved = try InputResolver.resolve([])
        } else if fileParts.isEmpty {
            resolved = [.text(messageText)]
        } else {
            resolved = try InputResolver.resolve(fileParts)
        }

        let prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: verbose)

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "messages", backend: "Messages.app (AppleScript)", items: prepared, openedNativeUI: false))
            } else {
                print("Would message \(resolvedRecipient)")
                if !messageText.isEmpty {
                    print("  text: \(messageText.prefix(80))")
                }
                for item in prepared where item.kind == .file {
                    print("  file: \(item.displayName)")
                }
                print("  send: \(shouldSend ? "yes" : "draft")")
            }
            return
        }

        if !quiet {
            if shouldSend {
                Log.info("Sending to \(resolvedRecipient)…")
            } else {
                Log.info("Opening Messages to \(resolvedRecipient)…")
            }
        }

        let options = MessagesOptions(
            recipient: resolvedRecipient,
            text: messageText.isEmpty ? nil : messageText,
            send: shouldSend
        )
        let backend = MessagesBackend(options: options)
        try backend.share(prepared)

        History.record(destination: "messages", recipient: resolvedRecipient, items: items, archivePath: nil)

        if shouldSend {
            Notifier.send(title: "share", message: "Sent to \(resolvedRecipient)")
        }

        if json {
            print(JSONOutput.success(destination: "messages", backend: backend.name, items: prepared, openedNativeUI: !shouldSend))
        }
    }
}
