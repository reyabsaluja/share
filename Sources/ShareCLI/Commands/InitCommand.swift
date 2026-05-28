import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Set up share config and aliases interactively."
    )

    func run() throws {
        print(Color.bold("share — setup\n"))

        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/share")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        print("Set up an alias? (e.g. 'rey' → 'rey@example.com')")
        fputs("  Name (or press Enter to skip): ", stderr)
        if let name = readLine(), !name.isEmpty {
            fputs("  Email or phone: ", stderr)
            if let value = readLine(), !value.isEmpty {
                try Aliases.set(name, value: value)
                print(Color.green("  ✓ @\(name) → \(value)"))
            }
        }

        print("")
        print("Set default --smart mode? (excludes .git, node_modules, etc.)")
        fputs("  Enable? [y/N]: ", stderr)
        if let answer = readLine(), answer.lowercased().hasPrefix("y") {
            let config = ShareConfig(defaultSmart: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configDir.appendingPathComponent("config.json"))
            print(Color.green("  ✓ Smart mode enabled by default"))
        }

        print("")
        print("Install shell completions?")
        fputs("  Shell (zsh/bash/fish or Enter to skip): ", stderr)
        if let shell = readLine(), !shell.isEmpty {
            var completionsCmd = CompletionsCommand()
            completionsCmd.shell = shell
            completionsCmd.install = true
            try completionsCmd.run()
        }

        print("")
        print(Color.bold("Done! Try:"))
        print("  share .              # AirDrop current dir")
        print("  share preview .      # See what would be shared")
        print("  share doctor         # Check system status")
        print("")
    }
}
