import ArgumentParser
import Foundation

/// Flags shared by every command that produces output.
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Show what would happen without doing it.")
    var dryRun = false

    @Flag(name: .long, help: "Print the result as JSON on stdout.")
    var json = false

    @Flag(name: [.customShort("v"), .long], help: "Print extra detail.")
    var verbose = false

    @Flag(name: [.short, .long], help: "Suppress status output. Errors are still printed.")
    var quiet = false

    @Flag(name: [.short, .long], help: "Answer yes to every confirmation prompt.")
    var yes = false

    @Flag(name: .long, help: "Force colored output.")
    var color = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    /// Pushes the flags into the process-wide settings. Call first thing in `run()`.
    func apply() {
        Log.verbose = verbose
        Log.quiet = quiet
        if yes { Prompt.assumeYes = true }
        if json { JSONOutput.enabled = true }
        if noColor { Color.mode = .never } else if color { Color.mode = .always }
    }
}

/// Flags shared by every command that can package directories.
struct PackagingOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Archive name, without the .zip extension.")
    var name: String?

    @Flag(name: .long, help: "Exclude VCS metadata, dependencies, build output and secrets (honors .gitignore and .shareignore).")
    var smart = false

    @Flag(name: .long, help: "Share directories as-is instead of zipping them.")
    var noZip = false

    @Option(name: .long, help: "Extra ignore pattern, gitignore style. Repeatable.")
    var exclude: [String] = []

    func prepareOptions(destination: String, output: OutputOptions) -> PrepareOptions {
        var options = PrepareOptions(destination: destination)
        options.smart = smart
        options.noZip = noZip
        options.archiveName = name
        options.excludePatterns = exclude
        options.verbose = output.verbose
        options.quiet = output.quiet
        options.dryRun = output.dryRun
        return options
    }
}

/// Small helpers that keep the commands short and consistent.
enum Runner {
    /// Prints the standard dry-run report.
    static func printDryRun(destination: String, recipient: String? = nil, items: [PreparedShareItem], json: Bool, details: [(String, String)] = []) {
        if json {
            var extra: [String: Any] = [:]
            if let r = recipient { extra["recipient"] = r }
            for (key, value) in details { extra[key] = value }
            print(JSONOutput.dryRun(destination: destination, items: items, extra: extra))
            return
        }
        let target = recipient.map { " → \($0)" } ?? ""
        print(Color.bold("Would \(destination)\(target)"))
        for item in items {
            let size = item.sizeDescription
            let sizeText = size.isEmpty ? "" : "  " + Color.dim("(\(size)\(item.packaged ? ", estimated" : ""))")
            if item.packaged, let url = item.fileURL {
                print("  package  \(item.originalDescription) → \(url.lastPathComponent)\(sizeText)")
            } else {
                print("  \(item.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(item.displayName)\(sizeText)")
            }
        }
        for (key, value) in details {
            print("  \(key.padding(toLength: 8, withPad: " ", startingAt: 0)) \(value)")
        }
    }

    /// Records history, notifies, and prints JSON after a successful share.
    static func finish(
        destination: String,
        backend: String,
        items: [PreparedShareItem],
        recipient: String?,
        sourceArguments: [String],
        openedNativeUI: Bool,
        json: Bool,
        successMessage: String? = nil
    ) {
        let archive = items.first(where: \.packaged)?.fileURL?.path
        History.record(
            destination: destination,
            recipient: recipient,
            items: sourceArguments.isEmpty ? ["."] : sourceArguments,
            archivePath: archive
        )
        if let message = successMessage {
            Log.success(message)
            Notifier.sendIfEnabled(message: message)
        }
        if json {
            print(JSONOutput.success(destination: destination, backend: backend, items: items, openedNativeUI: openedNativeUI))
        }
    }

    /// Announces packaged archives before handing off to a backend.
    static func announcePackaged(_ items: [PreparedShareItem]) {
        for item in items where item.packaged {
            if let url = item.fileURL {
                Log.info("Packaged → \(url.lastPathComponent) " + Color.dim("(\(item.sizeDescription))"))
            }
        }
    }

    /// Resolves a recipient argument (alias, group alias, email, phone) to a destination list.
    static func destinations(for recipient: String, allowBareAlias: Bool = false) throws -> [Destination] {
        let expanded = SmartRouter.recipients(from: recipient, allowBareAlias: allowBareAlias)
        guard !expanded.isEmpty else {
            throw ShareError.usage("no recipient given")
        }
        return try expanded.map { r in
            guard let destination = SmartRouter.detect(r) else {
                throw ShareError.usage(
                    "'\(r)' is not an email address, phone number or @alias",
                    hint: "create one with: share alias \(r.filter(\.isLetter).lowercased().prefix(12)) <email-or-phone>"
                )
            }
            return destination
        }
    }
}

/// Shell completion helper: suggests `@alias` names.
enum Completions {
    @Sendable static func aliasNames(_ words: [String], _ index: Int, _ prefix: String) -> [String] {
        return Aliases.names().map { "@" + $0 }.filter { prefix.isEmpty || $0.hasPrefix(prefix) }
    }
}
