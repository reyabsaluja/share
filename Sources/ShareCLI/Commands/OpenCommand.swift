import ArgumentParser
import Foundation

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open items in their default app, or reveal them in Finder.",
        aliases: ["reveal", "finder"]
    )

    @Argument(help: "Files, directories, or URLs. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions

    @Flag(name: [.short, .long], help: "Reveal in Finder instead of opening.")
    var reveal = false

    @Option(name: [.short, .long], help: "Open with a specific application, e.g. --app 'Visual Studio Code'.")
    var app: String?

    func run() throws {
        output.apply()
        let resolved = try InputResolver.resolve(items)

        for item in resolved {
            var arguments: [String] = []
            switch item {
            case .file(let url), .directory(let url):
                if reveal { arguments.append("-R") }
                if let app = app { arguments.append(contentsOf: ["-a", app]) }
                arguments.append(url.path)
            case .url(let url):
                if let app = app { arguments.append(contentsOf: ["-a", app]) }
                arguments.append(url.absoluteString)
            case .text:
                continue
            }
            if output.dryRun {
                print("Would run: open \(arguments.joined(separator: " "))")
                continue
            }
            let result = Subprocess.run("/usr/bin/open", arguments: arguments)
            guard result.status == 0 else {
                throw ShareError.sharingFailed("open failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }
}
