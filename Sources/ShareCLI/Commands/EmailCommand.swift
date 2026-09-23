import ArgumentParser
import Foundation

struct EmailCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "email",
        abstract: "Create a Mail.app draft (or send) with the items attached.",
        discussion: """
        URLs and text become part of the body; files and zipped directories are attached.
        Piped stdin is appended to the body. Use --send to send without reviewing.
        """,
        aliases: ["mail", "em"]
    )

    @Argument(help: "Recipient: email address, @alias, or comma-separated list.", completion: .custom(Completions.aliasNames))
    var to: String

    @Argument(help: "Files, directories, URLs, or - for stdin. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Option(name: [.short, .long], help: "Subject line. Default: \"Shared: <repo> (<branch>)\" or the configured template.")
    var subject: String?

    @Option(name: [.short, .long], help: "Body text. Use - to read it from stdin.")
    var body: String?

    @Option(name: .long, help: "Read the body from a file.")
    var bodyFile: String?

    @Option(name: .long, help: "Sender address (default: config 'from').")
    var from: String?

    @Option(name: .long, help: "CC recipients, comma-separated.")
    var cc: String?

    @Option(name: .long, help: "BCC recipients, comma-separated.")
    var bcc: String?

    @Flag(name: .long, help: "Send immediately instead of opening a draft.")
    var send = false

    func run() throws {
        output.apply()

        let recipients = SmartRouter.recipients(from: to)
        guard !recipients.isEmpty else { throw ShareError.usage("no recipient given") }
        for r in recipients where !SmartRouter.looksLikeEmail(r) {
            throw ShareError.usage("'\(r)' is not an email address", hint: "use an address like name@example.com, or an @alias that points to one")
        }
        let toList = recipients.joined(separator: ", ")

        let effectiveBody = try Self.resolveBody(body: body, bodyFile: bodyFile)
        let resolved = try InputResolver.resolve(items)
        let options = packaging.prepareOptions(destination: "email", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        let effectiveSubject = subject ?? defaultSubject(prepared)

        if output.dryRun {
            var details = [("subject", effectiveSubject), ("action", send ? "send" : "draft")]
            if let f = from ?? ShareConfig.current.from { details.append(("from", f)) }
            if let c = cc { details.append(("cc", c)) }
            if let b = bcc { details.append(("bcc", b)) }
            if let body = effectiveBody { details.append(("body", body.count > 60 ? String(body.prefix(60)) + "…" : body)) }
            Runner.printDryRun(destination: "email", recipient: toList, items: prepared, json: output.json, details: details)
            return
        }

        Runner.announcePackaged(prepared)
        Log.info(send ? "Sending to \(toList)…" : "Drafting to \(toList)…")

        let backend = MailBackend(options: MailOptions(
            to: toList,
            from: from,
            cc: cc,
            bcc: bcc,
            subject: effectiveSubject,
            body: effectiveBody,
            send: send
        ))
        try backend.share(prepared)

        Runner.finish(
            destination: "email",
            backend: backend.name,
            items: prepared,
            recipient: toList,
            sourceArguments: items,
            openedNativeUI: !send,
            json: output.json,
            successMessage: send ? "Sent to \(toList) ✓" : "Draft opened in Mail ✓"
        )
    }

    private func defaultSubject(_ prepared: [PreparedShareItem]) -> String {
        let files = prepared.filter { $0.kind == .file }
        if files.count == 1, let item = files.first {
            let name = item.packaged ? (item.originalDescription as NSString).lastPathComponent : item.displayName
            return GitContext.smartSubject(itemName: name)
        }
        return GitContext.smartSubject()
    }

    /// Combines --body, --body-file and piped stdin into one body.
    static func resolveBody(body: String?, bodyFile: String?) throws -> String? {
        var parts: [String] = []
        if let body = body {
            if body == "-" {
                guard let piped = StdinReader.readAll() else { throw ShareError.usage("--body - was given but stdin is empty") }
                parts.append(piped)
            } else {
                parts.append(body)
            }
        }
        if let path = bodyFile {
            let url = InputResolver.expandPath(path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw ShareError.inputNotFound(path)
            }
            parts.append(content)
        }
        if body != "-", let piped = StdinReader.readIfPiped() {
            parts.append(piped)
        }
        let joined = parts.joined(separator: "\n\n").trimmingCharacters(in: .newlines)
        return joined.isEmpty ? nil : joined
    }
}
