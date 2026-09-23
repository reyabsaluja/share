import ArgumentParser
import Foundation

struct AgainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "again",
        abstract: "Repeat the last share exactly as it was run.",
        aliases: ["last", "redo"]
    )

    @Flag(name: .long, help: "Show what the last share was without repeating it.")
    var dryRun = false

    @Option(name: [.short, .long], help: "Repeat the Nth most recent share instead of the last (1 = last).")
    var index: Int = 1

    func run() throws {
        let entries = History.load()
        guard !entries.isEmpty else {
            throw ShareError.usage("no previous share found", hint: "try: share airdrop . or share email user@example.com")
        }
        guard index >= 1 && index <= entries.count else {
            throw ShareError.usage("history has only \(entries.count) entries")
        }
        let entry = entries[entries.count - index]

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let when = formatter.string(from: entry.timestamp)
        let commandLine = (["share"] + entry.replayArguments).joined(separator: " ")

        if dryRun {
            print("Last share " + Color.dim("(\(when))") + ":")
            print("  command:     " + Color.bold(commandLine))
            print("  destination: \(entry.destination)")
            if let r = entry.recipient { print("  recipient:   " + Color.cyan(r)) }
            if let cwd = entry.cwd { print("  directory:   \(cwd)") }
            for item in entry.items { print("  item:        \(item)") }
            if let archive = entry.archivePath { print("  archive:     \(archive)") }
            return
        }

        let directory = entry.cwd.map { URL(fileURLWithPath: $0) }
        if let dir = directory, !FileManager.default.fileExists(atPath: dir.path) {
            throw ShareError.inputNotFound(dir.path)
        }

        Log.info("Repeating: " + Color.bold(commandLine) + (entry.cwd.map { Color.dim("  in \($0)") } ?? ""))

        let process = Process()
        process.executableURL = Paths.executableURL
        process.arguments = entry.replayArguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }
}
