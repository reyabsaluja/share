import ArgumentParser
import Foundation

struct AgainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "again",
        abstract: "Repeat the last share action.",
        aliases: ["last", "redo"]
    )

    @Flag(name: .long, help: "Show what the last action was without repeating.")
    var dryRun = false

    func run() throws {
        guard let entry = History.last() else {
            Log.error("no previous share action found")
            Log.hint("try: share airdrop . or share email user@example.com")
            throw ExitCode.failure
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: entry.timestamp)

        if dryRun {
            print("Last share " + Color.dim("(\(timeStr))") + ":")
            print("  destination: " + Color.bold(entry.destination))
            if let r = entry.recipient { print("  recipient:   " + Color.cyan(r)) }
            for item in entry.items { print("  item:        \(item)") }
            if let archive = entry.archivePath { print("  archive:     \(archive)") }
            return
        }

        let knownDestinations: Set<String> = [
            "airdrop", "email", "messages", "msg", "shortcut", "zip",
            "copy", "text", "diff", "batch", "qr", "screenshot", "open"
        ]
        guard knownDestinations.contains(entry.destination) else {
            throw ShareError.usage("Invalid history entry destination: '\(entry.destination)'")
        }

        let desc = "share \(entry.destination)\(entry.recipient.map { " \($0)" } ?? "") \(entry.items.joined(separator: " "))"
        Log.info("Repeating: " + Color.bold(desc))

        var args = ["share", entry.destination]
        if let r = entry.recipient { args.append(r) }
        args.append(contentsOf: entry.items)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        process.arguments = Array(args.dropFirst())
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExitCode(rawValue: process.terminationStatus)
        }
    }
}
