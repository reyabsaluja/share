import Foundation

/// One recorded share action. Older entries may lack `argv`/`cwd`; `share again`
/// falls back to reconstructing a command from the other fields in that case.
struct HistoryEntry: Codable {
    let timestamp: Date
    let destination: String
    let recipient: String?
    let items: [String]
    let archivePath: String?
    var argv: [String]?
    var cwd: String?

    init(timestamp: Date = Date(), destination: String, recipient: String?, items: [String], archivePath: String?, argv: [String]?, cwd: String?) {
        self.timestamp = timestamp
        self.destination = destination
        self.recipient = recipient
        self.items = items
        self.archivePath = archivePath
        self.argv = argv
        self.cwd = cwd
    }

    /// The command line that reproduces this entry.
    var replayArguments: [String] {
        if let argv = argv, !argv.isEmpty { return argv }
        var args = [destination]
        if let r = recipient { args.append(r) }
        args.append(contentsOf: items)
        return args
    }
}

/// Append-only log of share actions, capped at `historyLimit` entries.
enum History {
    static let defaultLimit = 100

    /// Set to false to suppress recording (used by `share again`, which delegates to a child process).
    static var recordingEnabled = true

    static func record(destination: String, recipient: String?, items: [String], archivePath: String?) {
        guard recordingEnabled else { return }
        var entries = load()
        let entry = HistoryEntry(
            destination: destination,
            recipient: recipient,
            items: items,
            archivePath: archivePath,
            argv: Array(CommandLine.arguments.dropFirst()),
            cwd: FileManager.default.currentDirectoryPath
        )
        entries.append(entry)
        let limit = max(1, ShareConfig.current.historyLimit ?? defaultLimit)
        if entries.count > limit { entries = Array(entries.suffix(limit)) }
        save(entries)
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: Paths.historyFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func last() -> HistoryEntry? {
        return load().last
    }

    static func clear() {
        try? FileManager.default.removeItem(at: Paths.historyFile)
    }

    private static func save(_ entries: [HistoryEntry]) {
        try? Paths.ensureConfigDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: Paths.historyFile, options: .atomic)
    }
}
