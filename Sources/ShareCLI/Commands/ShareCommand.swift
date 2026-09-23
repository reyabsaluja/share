import AppKit
import ArgumentParser
import Foundation

struct ShareCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "share",
        abstract: "Share files from your Mac terminal via AirDrop, Mail, Messages, Shortcuts, or a local link.",
        discussion: """
        Smart routing: with no subcommand, the arguments decide the destination.

          share                         AirDrop the current directory (zipped)
          share ./build.zip README.md   AirDrop those files
          share rey@example.com         Email the current directory as a draft
          share +14375550100 "hi"       Compose a Message
          share @rey ./report.pdf       Use an alias; groups fan out to everyone
          share airdrop|email|msg ...   Explicit destination with every option

        Setup:    share init, share alias rey rey@example.com, share config set smart true
        Inspect:  share preview ., share doctor, share history
        Repeat:   share again

        Safety defaults: email and messages create drafts unless --send is given,
        nothing is uploaded anywhere, and folders are scanned for secrets first.
        """,
        version: Version.current,
        subcommands: [
            AirDropCommand.self,
            EmailCommand.self,
            MessagesCommand.self,
            ShortcutCommand.self,
            ServeCommand.self,
            ZipCommand.self,
            CopyCommand.self,
            TextCommand.self,
            DiffCommand.self,
            BatchCommand.self,
            QRCommand.self,
            ScreenshotCommand.self,
            OpenCommand.self,
            PreviewCommand.self,
            AgainCommand.self,
            HistoryCommand.self,
            AliasCommand.self,
            ConfigCommand.self,
            CompletionsCommand.self,
            InitCommand.self,
            CleanCommand.self,
            DoctorCommand.self,
            DefaultCommand.self,
        ],
        defaultSubcommand: DefaultCommand.self
    )
}

/// Handles `share <anything>` when the first argument is not a subcommand.
struct DefaultCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_default",
        shouldDisplay: false
    )

    @Argument(parsing: .allUnrecognized, help: "Recipient and/or items.")
    var remaining: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Option(name: [.short, .long], help: "Email body or message text.")
    var body: String?

    @Option(name: .long, help: "Sender address for email.")
    var from: String?

    @Option(name: .long, help: "CC recipients for email (comma-separated).")
    var cc: String?

    @Option(name: .long, help: "BCC recipients for email (comma-separated).")
    var bcc: String?

    @Flag(name: .long, help: "Send immediately instead of leaving a draft (email and messages).")
    var send = false

    @Flag(name: .long, help: "Use the SMS account instead of iMessage.")
    var sms = false

    mutating func run() throws {
        output.apply()

        // Anything that still looks like a flag here is one we do not know.
        if let unknown = remaining.first(where: { $0.hasPrefix("-") && $0.count > 1 && !InputResolver.existsAsFile($0) }) {
            throw ShareError.usage("unknown option '\(unknown)'", hint: "run 'share --help' or 'share <command> --help' to see the available options")
        }

        let (recipient, items) = Self.splitRecipient(remaining)

        guard let recipient = recipient else {
            try runAirDrop(items: items)
            return
        }

        let destinations = try Runner.destinations(for: recipient, allowBareAlias: true)
        if destinations.count > 1 {
            try runBatch(destinations: destinations, recipientArgument: recipient, items: items)
            return
        }
        switch destinations[0] {
        case .email(let address): try runEmail(to: address, items: items)
        case .messages(let handle): try runMessages(to: handle, items: items)
        case .airdrop: try runAirDrop(items: items)
        }
    }

    /// Finds the first argument that names a recipient (and is not an existing path).
    static func splitRecipient(_ args: [String]) -> (String?, [String]) {
        for (index, arg) in args.enumerated() where !InputResolver.existsAsFile(arg) && !InputResolver.isURL(arg) && arg != "-" {
            let looksLikeRecipient = SmartRouter.detect(arg, allowBareAlias: true) != nil
                || arg.contains(",") && SmartRouter.recipients(from: arg, allowBareAlias: true).allSatisfy { SmartRouter.detect($0) != nil }
            if looksLikeRecipient {
                var rest = args
                rest.remove(at: index)
                return (arg, rest)
            }
        }
        return (nil, args)
    }

    // MARK: - Destinations

    /// Flags to forward to the concrete subcommand.
    private func forwardedFlags(packaging includePackaging: Bool) -> [String] {
        var flags: [String] = []
        if output.dryRun { flags.append("--dry-run") }
        if output.json { flags.append("--json") }
        if output.verbose { flags.append("--verbose") }
        if output.quiet { flags.append("--quiet") }
        if output.yes { flags.append("--yes") }
        if output.color { flags.append("--color") }
        if output.noColor { flags.append("--no-color") }
        if includePackaging {
            if let name = packaging.name { flags.append(contentsOf: ["--name", name]) }
            if packaging.smart { flags.append("--smart") }
            if packaging.noZip { flags.append("--no-zip") }
            for pattern in packaging.exclude { flags.append(contentsOf: ["--exclude", pattern]) }
        }
        return flags
    }

    private func forward<C: ParsableCommand>(_ type: C.Type, flags: [String], positionals: [String]) throws {
        var command = try type.parse(flags + ["--"] + positionals)
        try command.run()
    }

    private func runAirDrop(items: [String]) throws {
        try forward(AirDropCommand.self, flags: forwardedFlags(packaging: true), positionals: items)
    }

    private func runEmail(to address: String, items: [String]) throws {
        var flags = forwardedFlags(packaging: true)
        if let subject = subject { flags.append(contentsOf: ["--subject", subject]) }
        if let body = body { flags.append(contentsOf: ["--body", body]) }
        if let from = from { flags.append(contentsOf: ["--from", from]) }
        if let cc = cc { flags.append(contentsOf: ["--cc", cc]) }
        if let bcc = bcc { flags.append(contentsOf: ["--bcc", bcc]) }
        if send { flags.append("--send") }
        try forward(EmailCommand.self, flags: flags, positionals: [address] + items)
    }

    private func runMessages(to handle: String, items: [String]) throws {
        var flags = forwardedFlags(packaging: true)
        if let body = body { flags.append(contentsOf: ["--text", body]) }
        if send { flags.append("--send") }
        if sms { flags.append("--sms") }
        try forward(MessagesCommand.self, flags: flags, positionals: [handle] + items)
    }

    private func runBatch(destinations: [Destination], recipientArgument: String, items: [String]) throws {
        var flags = forwardedFlags(packaging: true)
        if let subject = subject { flags.append(contentsOf: ["--subject", subject]) }
        if let body = body { flags.append(contentsOf: ["--body", body]) }
        if send { flags.append("--send") }
        try forward(BatchCommand.self, flags: flags, positionals: [recipientArgument] + items)
    }
}
