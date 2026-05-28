import ArgumentParser
import Foundation

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent share actions.",
        aliases: ["log"]
    )

    @Option(name: [.short, .long], help: "Number of entries to show.")
    var count: Int = 10

    @Flag(name: .long, help: "Clear all history.")
    var clear = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        if clear {
            History.clear()
            print("History cleared.")
            return
        }

        let entries = History.load()

        if entries.isEmpty {
            print("No share history yet.")
            Log.hint("try: share airdrop . or share email user@example.com")
            return
        }

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(entries.suffix(count)))
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        print("")
        let recent = entries.suffix(count).reversed()
        for entry in recent {
            let ago = relativeTime(entry.timestamp)
            let icon = destinationIcon(entry.destination)
            let recipient = entry.recipient.map { Color.cyan($0) } ?? ""
            let items = entry.items.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            let desc = [recipient, items].filter { !$0.isEmpty }.joined(separator: " ")
            let timeStr = Color.dim(ago.padding(toLength: 12, withPad: " ", startingAt: 0))
            print("  \(icon) \(timeStr) \(desc)")
        }
        print("")
    }

    private func destinationIcon(_ dest: String) -> String {
        switch dest {
        case "airdrop": return "📡"
        case "email": return "✉️ "
        case "messages": return "💬"
        case "screenshot": return "📸"
        case "zip": return "📦"
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
