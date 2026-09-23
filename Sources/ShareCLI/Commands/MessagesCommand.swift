import ArgumentParser
import Foundation

struct MessagesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "messages",
        abstract: "Share via Messages (iMessage or SMS).",
        discussion: "Arguments that are not existing files become the message text. Without --send, the conversation opens with the text pre-filled and any files on the clipboard (⌘V to attach). With --send, text and files go out immediately.",
        aliases: ["message", "msg", "im", "sms"]
    )

    @Argument(help: "Recipient: phone number, iMessage email, or @alias.", completion: .custom(Completions.aliasNames))
    var recipient: String

    @Argument(help: "Text, files, directories, or URLs.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Option(name: [.short, .long], help: "Message text (alternative to positional words). Use - for stdin.")
    var text: String?

    @Flag(name: .long, help: "Send immediately instead of opening a draft.")
    var send = false

    @Flag(name: .long, help: "Use the SMS account (iPhone relay) instead of iMessage.")
    var sms = false

    func run() throws {
        output.apply()

        let resolvedRecipient = Aliases.resolve(recipient) ?? recipient
        guard let destination = SmartRouter.detect(resolvedRecipient), let handle = destination.recipient else {
            throw ShareError.usage("'\(recipient)' is not a phone number, email address or @alias")
        }

        var words: [String] = []
        var paths: [String] = []
        for item in items {
            if InputResolver.existsAsFile(item) || item == "-" {
                paths.append(item)
            } else if InputResolver.isURL(item) {
                words.append(item)
            } else {
                words.append(item)
            }
        }

        var messageText: String
        if let explicit = text {
            if explicit == "-" {
                guard let piped = StdinReader.readAll() else { throw ShareError.usage("--text - was given but stdin is empty") }
                messageText = piped
            } else {
                messageText = explicit
            }
        } else if !words.isEmpty {
            messageText = words.joined(separator: " ")
        } else if let piped = StdinReader.readIfPiped() {
            messageText = piped
        } else {
            messageText = ""
        }
        messageText = messageText.trimmingCharacters(in: .newlines)

        let resolved: [ShareItem]
        if paths.isEmpty && messageText.isEmpty {
            resolved = try InputResolver.resolve([])
        } else if paths.isEmpty {
            resolved = []
        } else {
            resolved = try InputResolver.resolve(paths)
        }

        let options = packaging.prepareOptions(destination: "messages", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        if output.dryRun {
            var details: [(String, String)] = []
            if !messageText.isEmpty { details.append(("text", String(messageText.prefix(80)))) }
            details.append(("action", send ? "send" : "draft"))
            details.append(("service", (sms || ShareConfig.current.sms == true) ? "SMS" : "iMessage"))
            Runner.printDryRun(destination: "messages", recipient: handle, items: prepared, json: output.json, details: details)
            return
        }

        Runner.announcePackaged(prepared)
        Log.info(send ? "Sending to \(handle)…" : "Opening Messages for \(handle)…")

        let backend = MessagesBackend(options: MessagesOptions(
            recipient: handle,
            text: messageText.isEmpty ? nil : messageText,
            send: send,
            sms: sms
        ))
        try backend.share(prepared)

        Runner.finish(
            destination: "messages",
            backend: backend.name,
            items: prepared,
            recipient: handle,
            sourceArguments: items,
            openedNativeUI: !send,
            json: output.json,
            successMessage: send ? "Sent to \(handle) ✓" : nil
        )
    }
}
