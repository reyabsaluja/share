import Foundation

struct HistoryEntry: Codable {
    let timestamp: Date
    let destination: String
    let recipient: String?
    let items: [String]
    let archivePath: String?
}

enum History {
    private static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/share/history.json")
    }

    static func record(destination: String, recipient: String?, items: [String], archivePath: String?) {
        var entries = load()
        let entry = HistoryEntry(
            timestamp: Date(),
            destination: destination,
            recipient: recipient,
            items: items,
            archivePath: archivePath
        )
        entries.append(entry)
        if entries.count > 50 { entries = Array(entries.suffix(50)) }
        save(entries)
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func last() -> HistoryEntry? {
        return load().last
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func save(_ entries: [HistoryEntry]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
