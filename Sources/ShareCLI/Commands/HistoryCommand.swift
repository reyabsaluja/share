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

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        let recent = entries.suffix(count).reversed()
        for entry in recent {
            let ago = formatter.localizedString(for: entry.timestamp, relativeTo: Date())
            let recipient = entry.recipient ?? ""
            let items = entry.items.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            let desc = [entry.destination, recipient, items].filter { !$0.isEmpty }.joined(separator: " ")
            print("  \(ago.padding(toLength: 10, withPad: " ", startingAt: 0)) \(desc)")
        }
    }
}
