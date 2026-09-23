import ArgumentParser
import Foundation

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent shares.",
        aliases: ["log"]
    )

    @Option(name: [.short, .long], help: "Number of entries to show.")
    var count: Int = 10

    @Flag(name: .long, help: "Show every entry.")
    var all = false

    @Flag(name: .long, help: "Delete the history file.")
    var clear = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    @Flag(name: [.short, .long], help: "Answer yes to confirmations.")
    var yes = false

    func run() throws {
        if yes { Prompt.assumeYes = true }
        if clear {
            let entries = History.load()
            guard !entries.isEmpty else { print("History is already empty."); return }
            if Prompt.confirm("Delete \(HumanReadable.count(entries.count, "history entry", "history entries"))?") != true {
                throw ShareError.userCancelled
            }
            History.clear()
            print("History cleared.")
            return
        }

        let entries = History.load()
        if entries.isEmpty {
            if json { print("[]"); return }
            print("No shares yet.")
            Log.hint("try: share airdrop . or share email user@example.com")
            return
        }

        let shown = all ? entries : Array(entries.suffix(max(1, count)))

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(shown), encoding: .utf8) ?? "[]")
            return
        }

        print("")
        for (offset, entry) in shown.reversed().enumerated() {
            let ago = relativeTime(entry.timestamp)
            let icon = destinationIcon(entry.destination)
            let recipient = entry.recipient.map { Color.cyan($0) } ?? ""
            let items = entry.items.map { $0 == "." ? (entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent + "/" } ?? ".") : URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            let desc = [recipient, items].filter { !$0.isEmpty }.joined(separator: "  ")
            let index = Color.dim(String(offset + 1).padding(toLength: 3, withPad: " ", startingAt: 0))
            let time = Color.dim(ago.padding(toLength: 10, withPad: " ", startingAt: 0))
            print("  \(index)\(icon) \(entry.destination.padding(toLength: 10, withPad: " ", startingAt: 0)) \(time) \(desc)")
        }
        print("")
        Log.hint("repeat one with: share again --index <n>")
    }

    private func destinationIcon(_ dest: String) -> String {
        switch dest {
        case "airdrop": return "📡"
        case "email": return "✉️ "
        case "messages": return "💬"
        case "screenshot": return "📸"
        case "zip": return "📦"
        case "serve": return "🌐"
        case "diff": return "🩹"
        default: return "→ "
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 172800 { return "yesterday" }
        if seconds < 604800 { return "\(seconds / 86400)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
