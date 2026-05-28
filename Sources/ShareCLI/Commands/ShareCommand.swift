import AppKit
import ArgumentParser
import Foundation

@main
struct ShareCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "share",
        abstract: "Share files from your Mac terminal via AirDrop, Mail, Messages, and Shortcuts.",
        discussion: """
        Smart routing: the first argument determines the destination.

          share                        AirDrop current directory
          share ./file.txt             AirDrop that file
          share rey@email.com          Email current directory
          share +14375551234 hello     Compose a message
          share @rey README.md         Use alias (@name)
          share airdrop/email/msg ...  Explicit destination

        Set up aliases:  share alias rey rey@example.com
        Preview first:   share preview .
        Repeat last:     share again
        """,
        version: "0.1.0",
        subcommands: [
            AirDropCommand.self,
            EmailCommand.self,
            MessagesCommand.self,
            ShortcutCommand.self,
            ZipCommand.self,
            CopyCommand.self,
            TextCommand.self,
            DiffCommand.self,
            BatchCommand.self,
            QRCommand.self,
            OpenCommand.self,
            PreviewCommand.self,
            AgainCommand.self,
            HistoryCommand.self,
            AliasCommand.self,
            CleanCommand.self,
            DoctorCommand.self,
            DefaultCommand.self,
        ],
        defaultSubcommand: DefaultCommand.self
    )
}

struct DefaultCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_default",
        shouldDisplay: false
    )

    @Argument(parsing: .allUnrecognized)
    var remaining: [String] = []

    @Flag(name: .long, help: "Show what would happen without sharing.")
    var dryRun = false

    @Flag(name: .long, help: "Output result as JSON.")
    var json = false

    @Flag(name: .long, help: "Print verbose output.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Option(name: [.short, .long], help: "Archive name.")
    var name: String?

    @Flag(name: .long, help: "Send immediately (email and messages default to draft).")
    var send = false

    @Flag(name: .long, help: "Don't zip directories.")
    var noZip = false

    @Flag(name: .long, help: "Skip confirmation prompts.")
    var yes = false

    mutating func run() throws {
        Log.verbose = verbose
        Log.quiet = quiet

        let args = remaining.filter { !$0.hasPrefix("-") }

        if args.isEmpty {
            try runAirDrop(items: [])
            return
        }

        let first = args[0]
        let rest = Array(args.dropFirst())

        if let destination = SmartRouter.detect(first) {
            switch destination {
            case .email(let address):
                try runEmail(to: address, items: rest)
            case .messages(let recipient):
                try runMessages(to: recipient, items: rest)
            case .airdrop:
                try runAirDrop(items: args)
            }
        } else {
            try runAirDrop(items: args)
        }
    }

    private func runAirDrop(items: [String]) throws {
        let resolved = try InputResolver.resolve(items)

        if !yes && !dryRun {
            for item in resolved {
                if case .directory(let url) = item {
                    guard SecretsDetector.warnIfNeeded(directory: url, quiet: quiet) else {
                        throw ShareError.userCancelled
                    }
                }
            }
        }

        let prepared: [PreparedShareItem]
        if noZip {
            prepared = resolved.map { $0.toPrepared() }
        } else {
            prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: verbose)
        }

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "airdrop", backend: "NSSharingService.sendViaAirDrop", items: prepared, openedNativeUI: false))
            } else {
                for item in prepared {
                    if item.packaged, case .file(let url) = item.value {
                        let size = HumanReadable.fileSizeAt(url.path) ?? ""
                        print("Would package → \(url.lastPathComponent) (\(size))")
                    } else {
                        print("Would AirDrop: \(item.displayName)")
                    }
                }
            }
            return
        }

        if !quiet {
            Log.info("Opening AirDrop…")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let backend = AirDropBackend()
        try backend.share(prepared)

        let itemPaths = items.isEmpty ? ["."] : items
        History.record(destination: "airdrop", recipient: nil, items: itemPaths, archivePath: prepared.first(where: \.packaged).flatMap { if case .file(let u) = $0.value { return u.path }; return nil })

        if json {
            print(JSONOutput.success(destination: "airdrop", backend: backend.name, items: prepared, openedNativeUI: true))
        }
    }

    private func runEmail(to address: String, items: [String]) throws {
        let stdinText = StdinReader.readIfPiped()
        let resolved = try InputResolver.resolve(items)

        if !yes && !dryRun {
            for item in resolved {
                if case .directory(let url) = item {
                    guard SecretsDetector.warnIfNeeded(directory: url, quiet: quiet) else {
                        throw ShareError.userCancelled
                    }
                }
            }
        }

        let prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: verbose)

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "email", backend: "Mail.app (AppleScript)", items: prepared, openedNativeUI: false))
            } else {
                print("Would email \(address)")
                for item in prepared {
                    print("  attach: \(item.displayName)")
                }
            }
            return
        }

        if !quiet {
            Log.info("Drafting email to \(address)…")
        }

        let effectiveSubject = subject ?? GitContext.smartSubject()

        let options = MailOptions(
            to: address,
            subject: effectiveSubject,
            body: stdinText,
            send: send
        )
        let backend = MailBackend(options: options)
        try backend.share(prepared)

        History.record(destination: "email", recipient: address, items: items.isEmpty ? ["."] : items, archivePath: nil)

        if json {
            print(JSONOutput.success(destination: "email", backend: backend.name, items: prepared, openedNativeUI: !send))
        }
    }

    private func runMessages(to recipient: String, items: [String]) throws {
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
        if !textParts.isEmpty {
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
                print("Would message \(recipient)")
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
                Log.info("Sending to \(recipient)…")
            } else {
                Log.info("Opening Messages to \(recipient)…")
            }
        }

        let options = MessagesOptions(
            recipient: recipient,
            text: messageText.isEmpty ? nil : messageText,
            send: shouldSend
        )
        let backend = MessagesBackend(options: options)
        try backend.share(prepared)

        History.record(destination: "messages", recipient: recipient, items: items, archivePath: nil)
        if shouldSend {
            Notifier.send(title: "share", message: "Sent to \(recipient)")
        }

        if json {
            print(JSONOutput.success(destination: "messages", backend: backend.name, items: prepared, openedNativeUI: !shouldSend))
        }
    }
}
