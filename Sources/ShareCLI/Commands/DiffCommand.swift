import ArgumentParser
import Foundation

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Share the current git diff by email, Messages, or AirDrop.",
        discussion: """
        Short diffs are sent inline; long ones (or --attach) are sent as a .patch file.
        Examples:
          share diff rey@example.com
          share diff @rey --staged
          share diff +14375550100 --range main..HEAD --send
          share diff airdrop
        """
    )

    @Argument(help: "Recipient (email, phone, @alias) or 'airdrop'.", completion: .custom(Completions.aliasNames))
    var recipient: String

    @Argument(help: "Limit the diff to these paths.")
    var paths: [String] = []

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Diff the staged changes only.")
    var staged = false

    @Option(name: .long, help: "Git revision range, e.g. main..HEAD or HEAD~3.")
    var range: String?

    @Option(name: [.short, .long], help: "Email subject.")
    var subject: String?

    @Flag(name: .long, help: "Always attach as a .patch file instead of inlining.")
    var attach = false

    @Flag(name: .long, help: "Send immediately instead of opening a draft.")
    var send = false

    static let inlineLineLimit = 400

    func run() throws {
        output.apply()

        guard GitContext.repoRoot() != nil else {
            throw ShareError.usage("not inside a git repository")
        }
        guard let diff = GitContext.diff(range: range, staged: staged, paths: paths), !diff.isEmpty else {
            let what = staged ? "no staged changes" : (range.map { "no changes in \($0)" } ?? "no unstaged changes")
            throw ShareError.usage("\(what) to share", hint: staged ? "stage something first, or drop --staged" : "make some changes, or use --staged / --range")
        }

        let lineCount = diff.components(separatedBy: .newlines).count
        let label = staged ? "Staged changes" : "Changes"
        let effectiveSubject = subject ?? GitContext.smartSubject(for: label)
        let shouldAttach = attach || lineCount > Self.inlineLineLimit

        let destinations = try Runner.destinations(for: recipient)
        for destination in destinations {
            switch destination {
            case .email(let address):
                let items: [PreparedShareItem] = shouldAttach ? [try patchFile(diff)] : []
                if output.dryRun {
                    let textItem = PreparedShareItem(kind: .text, originalDescription: "diff", value: .text("\(lineCount) lines"), packaged: false, temporary: false, sizeBytes: Int64(diff.utf8.count))
                    Runner.printDryRun(destination: "email", recipient: address, items: items.isEmpty ? [textItem] : items, json: output.json, details: [("subject", effectiveSubject), ("lines", "\(lineCount)"), ("action", send ? "send" : "draft")])
                    continue
                }
                Log.info((send ? "Sending diff to " : "Drafting diff to ") + address + " " + Color.dim("(\(lineCount) lines\(shouldAttach ? ", attached" : ""))"))
                let backend = MailBackend(options: MailOptions(to: address, subject: effectiveSubject, body: shouldAttach ? nil : diff, send: send))
                try backend.share(items)
                Runner.finish(destination: "diff", backend: backend.name, items: items, recipient: address, sourceArguments: paths, openedNativeUI: !send, json: output.json)

            case .messages(let handle):
                let items = [try patchFile(diff)]
                if output.dryRun {
                    Runner.printDryRun(destination: "messages", recipient: handle, items: items, json: output.json, details: [("lines", "\(lineCount)"), ("action", send ? "send" : "draft")])
                    continue
                }
                Log.info((send ? "Sending diff to " : "Opening Messages for ") + handle + " " + Color.dim("(\(lineCount) lines)"))
                let backend = MessagesBackend(options: MessagesOptions(recipient: handle, text: effectiveSubject, send: send))
                try backend.share(items)
                Runner.finish(destination: "diff", backend: backend.name, items: items, recipient: handle, sourceArguments: paths, openedNativeUI: !send, json: output.json)

            case .airdrop:
                let items = [try patchFile(diff)]
                if output.dryRun {
                    Runner.printDryRun(destination: "airdrop", items: items, json: output.json, details: [("lines", "\(lineCount)")])
                    continue
                }
                Log.info("Opening AirDrop… " + Color.dim("(\(lineCount) lines)"))
                let backend = AirDropBackend()
                try backend.share(items)
                Runner.finish(destination: "diff", backend: backend.name, items: items, recipient: nil, sourceArguments: paths, openedNativeUI: true, json: output.json)
            }
        }
    }

    private func patchFile(_ diff: String) throws -> PreparedShareItem {
        let base = GitContext.repoName() ?? "changes"
        let branch = GitContext.branchName().map(GitContext.sanitize) ?? "diff"
        let url = Packager.tempDirectory().appendingPathComponent("\(base)-\(branch)-\(DateSlug.current()).patch")
        try diff.write(to: url, atomically: true, encoding: .utf8)
        TempFiles.register(url)
        return PreparedShareItem(kind: .file, originalDescription: "git diff", value: .file(url), packaged: false, temporary: true, sizeBytes: Int64(diff.utf8.count))
    }
}
