import ArgumentParser
import AppKit
import Foundation

struct BatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Share to multiple recipients at once.",
        aliases: ["multi"]
    )

    @Argument(help: "Recipients and items. Use commas between recipients: rey@a.com,bob@b.com ./file")
    var args: [String] = []

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Option(name: [.short, .long], help: "Archive name.")
    var name: String?

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.quiet = quiet

        guard !args.isEmpty else {
            throw ShareError.usage("Provide recipients and optionally files: share batch rey@a.com,+1234567890 ./file")
        }

        let first = args[0]
        let rest = Array(args.dropFirst())

        let recipientList = first.split(separator: ",").map(String.init)
        guard !recipientList.isEmpty else {
            throw ShareError.usage("No recipients found. Separate with commas: rey@a.com,bob@b.com")
        }

        let resolved = try InputResolver.resolve(rest)
        let prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: false)

        if dryRun {
            for recipient in recipientList {
                let dest = SmartRouter.detect(recipient)
                let destName: String
                switch dest {
                case .email: destName = "email"
                case .messages: destName = "messages"
                case .airdrop, .none: destName = "airdrop"
                }
                print("Would share via \(destName) to \(recipient)")
            }
            for item in prepared {
                print("  item: \(item.displayName)")
            }
            return
        }

        var successes = 0
        var failures = 0

        for recipient in recipientList {
            let resolvedRecipient = Aliases.resolve(recipient) ?? recipient
            guard let destination = SmartRouter.detect(resolvedRecipient) else {
                Log.error("can't determine destination for '\(recipient)' — skipping")
                failures += 1
                continue
            }

            do {
                switch destination {
                case .email(let address):
                    if !quiet { Log.info("Drafting to \(address)…") }
                    let options = MailOptions(
                        to: address,
                        subject: subject ?? GitContext.smartSubject(),
                        send: false
                    )
                    let backend = MailBackend(options: options)
                    try backend.share(prepared)
                    successes += 1

                case .messages(let phone):
                    if !quiet { Log.info("Sending to \(phone)…") }
                    let options = MessagesOptions(recipient: phone, text: nil, send: true)
                    let backend = MessagesBackend(options: options)
                    try backend.share(prepared)
                    successes += 1

                case .airdrop:
                    break
                }
            } catch {
                Log.error("failed for \(recipient): \(error)")
                failures += 1
            }
        }

        if !quiet {
            if failures == 0 {
                Log.info("Done: \(successes) recipients")
            } else {
                Log.info("Done: \(successes) succeeded, \(failures) failed")
            }
        }

        History.record(
            destination: "batch",
            recipient: recipientList.joined(separator: ","),
            items: rest.isEmpty ? ["."] : rest,
            archivePath: nil
        )
    }
}
