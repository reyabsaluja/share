import ArgumentParser
import Foundation

struct EmailCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "email",
        abstract: "Create a Mail.app draft with attachments.",
        aliases: ["mail", "em"]
    )

    @Argument(help: "Recipient email address.")
    var to: String

    @Argument(help: "Files, directories, or URLs to attach. Defaults to current directory.")
    var items: [String] = []

    @Option(name: [.short, .long], help: "Subject line.")
    var subject: String?

    @Option(name: [.short, .long], help: "Body text.")
    var body: String?

    @Option(name: .long, help: "Sender email.")
    var from: String?

    @Option(name: .long, help: "CC recipient.")
    var cc: String?

    @Option(name: .long, help: "BCC recipient.")
    var bcc: String?

    @Option(name: [.short, .long], help: "Archive name.")
    var name: String?

    @Flag(name: .long, help: "Send immediately (default is draft).")
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

        let resolvedTo = Aliases.resolve(to) ?? to

        let stdinText = StdinReader.readIfPiped()
        let effectiveBody: String?
        if let piped = stdinText {
            effectiveBody = body.map { $0 + "\n\n" + piped } ?? piped
        } else {
            effectiveBody = body
        }

        let resolved = try InputResolver.resolve(items)
        let prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: verbose)

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "email", backend: "Mail.app (AppleScript)", items: prepared, openedNativeUI: false))
            } else {
                print("Would email \(resolvedTo)")
                if let s = subject { print("  subject: \(s)") }
                for item in prepared {
                    print("  attach:  \(item.displayName)")
                }
                if send { print("  action:  send") } else { print("  action:  draft") }
            }
            return
        }

        if !quiet {
            if send {
                Log.info("Sending to \(resolvedTo)…")
            } else {
                Log.info("Drafting to \(resolvedTo)…")
            }
        }

        let options = MailOptions(
            to: resolvedTo,
            from: from,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: effectiveBody,
            send: send
        )
        let backend = MailBackend(options: options)
        try backend.share(prepared)

        if json {
            print(JSONOutput.success(destination: "email", backend: backend.name, items: prepared, openedNativeUI: !send))
        }
    }
}
