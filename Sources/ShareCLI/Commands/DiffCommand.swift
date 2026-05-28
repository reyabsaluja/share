import ArgumentParser
import Foundation

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Share git diff via email or messages."
    )

    @Argument(help: "Recipient (email or phone). Uses smart routing.")
    var recipient: String

    @Flag(name: .long, help: "Share staged changes only.")
    var staged = false

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.quiet = quiet

        let diffContent: String?
        if staged {
            diffContent = GitContext.diffStaged()
        } else {
            diffContent = GitContext.diff()
        }

        guard let diff = diffContent, !diff.isEmpty else {
            Log.error("no changes to share" + (staged ? " (staged)" : ""))
            throw ExitCode.failure
        }

        let effectiveSubject = subject ?? GitContext.smartSubject(for: staged ? "Staged changes" : "Changes")

        if let destination = SmartRouter.detect(recipient) {
            switch destination {
            case .email(let address):
                if dryRun {
                    print("Would email diff to \(address)")
                    print("  subject: \(effectiveSubject)")
                    print("  diff: \(diff.components(separatedBy: .newlines).count) lines")
                    return
                }

                if !quiet { Log.info("Emailing diff to \(address)…") }

                let options = MailOptions(
                    to: address,
                    subject: effectiveSubject,
                    body: diff,
                    send: false
                )
                let backend = MailBackend(options: options)
                try backend.share([])

            case .messages(let phone):
                let truncated = diff.count > 2000 ? String(diff.prefix(2000)) + "\n… (truncated)" : diff

                if dryRun {
                    print("Would message diff to \(phone)")
                    print("  lines: \(diff.components(separatedBy: .newlines).count)")
                    return
                }

                if !quiet { Log.info("Sending diff to \(phone)…") }

                let options = MessagesOptions(recipient: phone, text: truncated, send: true)
                let backend = MessagesBackend(options: options)
                try backend.share([ShareItem.text(truncated).toPrepared()])

            case .airdrop:
                break
            }
        } else {
            throw ShareError.usage("Recipient must be an email or phone number")
        }
    }
}
