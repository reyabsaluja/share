import ArgumentParser
import Foundation

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Reveal file in Finder or open in default app.",
        aliases: ["reveal", "finder"]
    )

    @Argument(help: "Files or directories to open. Defaults to current directory.")
    var items: [String] = []

    @Flag(name: [.short, .long], help: "Reveal in Finder instead of opening.")
    var reveal = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.quiet = quiet
        let resolved = try InputResolver.resolve(items)

        for item in resolved {
            switch item {
            case .file(let url), .directory(let url):
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = reveal ? ["-R", url.path] : [url.path]
                try process.run()
                process.waitUntilExit()
            case .url(let url):
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [url.absoluteString]
                try process.run()
                process.waitUntilExit()
            case .text:
                break
            }
        }
    }
}
