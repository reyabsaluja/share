import ArgumentParser
import Foundation

struct BatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Share the same items with several recipients at once.",
        discussion: "Recipients are comma-separated and may mix emails, phone numbers and @aliases (including group aliases). Items are packaged once and reused for every recipient.",
        aliases: ["multi"]
    )

    @Argument(help: "Comma-separated recipients: rey@a.com,+14375550100,@team", completion: .custom(Completions.aliasNames))
    var recipients: String

    @Argument(help: "Files, directories, or URLs. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Option(name: [.short, .long], help: "Email body or message text.")
    var body: String?

    @Flag(name: .long, help: "Send immediately instead of opening drafts.")
    var send = false

    func run() throws {
        output.apply()

        let destinations = try Runner.destinations(for: recipients)
        guard !destinations.isEmpty else { throw ShareError.usage("no recipients given") }

        let resolved = try InputResolver.resolve(items)
        let options = packaging.prepareOptions(destination: "email", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        if output.dryRun {
            let list = destinations.map { "\($0.name):\($0.recipient ?? "")" }.joined(separator: ", ")
            Runner.printDryRun(destination: "batch", recipient: list, items: prepared, json: output.json, details: [("action", send ? "send" : "draft")])
            return
        }

        Runner.announcePackaged(prepared)

        var succeeded: [String] = []
        var failed: [(String, String)] = []

        for destination in destinations {
            do {
                switch destination {
                case .email(let address):
                    Log.info((send ? "Sending to " : "Drafting to ") + address + "…")
                    let backend = MailBackend(options: MailOptions(to: address, subject: subject ?? GitContext.smartSubject(), body: body, send: send))
                    try backend.share(prepared)
                    succeeded.append(address)
                case .messages(let handle):
                    Log.info((send ? "Sending to " : "Opening Messages for ") + handle + "…")
                    let backend = MessagesBackend(options: MessagesOptions(recipient: handle, text: body, send: send))
                    try backend.share(prepared)
                    succeeded.append(handle)
                case .airdrop:
                    Log.info("Opening AirDrop…")
                    try AirDropBackend().share(prepared)
                    succeeded.append("airdrop")
                }
            } catch let error as ShareError {
                Log.error("\(destination.recipient ?? destination.name): \(error.description)")
                failed.append((destination.recipient ?? destination.name, error.description))
            }
        }

        if failed.isEmpty {
            Log.success("Done: \(HumanReadable.count(succeeded.count, "recipient")) ✓")
        } else {
            Log.warn("\(succeeded.count) succeeded, \(failed.count) failed")
        }

        History.record(destination: "batch", recipient: recipients, items: items.isEmpty ? ["."] : items, archivePath: prepared.first(where: \.packaged)?.fileURL?.path)

        if output.json {
            print(JSONOutput.format([
                "ok": failed.isEmpty,
                "destination": "batch",
                "succeeded": succeeded,
                "failed": failed.map { ["recipient": $0.0, "error": $0.1] },
                "items": prepared.map(JSONOutput.describe),
            ] as [String: Any]))
        }

        if succeeded.isEmpty && !failed.isEmpty {
            throw ShareError.sharingFailed("all \(failed.count) recipients failed")
        }
    }
}
