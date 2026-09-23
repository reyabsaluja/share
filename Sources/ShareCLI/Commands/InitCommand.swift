import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Interactive first-run setup: aliases, defaults, and shell completions."
    )

    func run() throws {
        guard Prompt.isInteractive else {
            throw ShareError.usage("share init needs a terminal", hint: "use 'share alias' and 'share config set' for scripted setup")
        }

        print(Color.bold("share — setup"))
        print(Color.dim("config: \(Paths.configDirectory.path)"))
        print("")
        try Paths.ensureConfigDirectory()

        print("1. Aliases let you type " + Color.cyan("share @rey .") + " instead of an address.")
        while true {
            guard let name = Prompt.ask("   Alias name (Enter to skip): "), !name.isEmpty else { break }
            guard let value = Prompt.ask("   Email, phone, or comma-separated group: "), !value.isEmpty else { break }
            do {
                for part in SmartRouter.recipients(from: value) where SmartRouter.detect(part) == nil {
                    throw ShareError.usage("'\(part)' is not an email address or phone number")
                }
                try Aliases.set(name, value: value)
                print(Color.green("   ✓ @\(name) → \(value)"))
            } catch let error as ShareError {
                Log.error(error.description)
            }
            if Prompt.confirm("   Add another?", defaultAnswer: false) != true { break }
        }

        print("")
        print("2. Smart mode skips .git, node_modules, build output and secrets when sharing folders.")
        var config = ShareConfig.read(from: Paths.configFile) ?? .empty
        if Prompt.confirm("   Enable smart mode by default?", defaultAnswer: true) == true {
            config.smart = true
            print(Color.green("   ✓ smart = true"))
        }

        print("")
        print("3. Email drafts get a subject like \"Shared: repo (branch)\".")
        if let from = Prompt.ask("   Default sender address for email (Enter to skip): "), !from.isEmpty {
            if SmartRouter.looksLikeEmail(from) {
                config.from = from
                print(Color.green("   ✓ from = \(from)"))
            } else {
                Log.warn("'\(from)' does not look like an email address; skipped")
            }
        }
        try ShareConfig.write(config, to: Paths.configFile)

        print("")
        print("4. Shell completions.")
        let detected = CompletionsCommand.detectShell()
        if Prompt.confirm("   Install \(detected) completions?", defaultAnswer: true) == true {
            var completions = CompletionsCommand()
            completions.shell = detected
            completions.install = true
            do { try completions.run() } catch let error as ShareError { Log.error(error.description) }
        }

        print("")
        print(Color.bold("Done. Try:"))
        print("  share .              AirDrop this folder")
        print("  share preview .      see what would be shared")
        print("  share @name file     email or message an alias")
        print("  share doctor         check your setup")
        print("")
    }
}
