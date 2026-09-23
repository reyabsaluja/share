import Foundation

/// Recipient aliases: `@rey` → `rey@example.com`, `@team` → `a@x.com,b@y.com`.
///
/// Stored as a flat JSON object in `~/.config/share/aliases.json`.
enum Aliases {
    /// Resolves `@name` (or a bare `name` when `allowBare` is set) to its value.
    static func resolve(_ name: String, allowBare: Bool = false) -> String? {
        let key: String
        if name.hasPrefix("@") {
            key = String(name.dropFirst())
        } else if allowBare {
            key = name
        } else {
            return nil
        }
        guard !key.isEmpty else { return nil }
        return load()[key]
    }

    /// Resolves an alias and splits comma-separated group values into individual recipients.
    static func expand(_ name: String, allowBare: Bool = false) -> [String]? {
        guard let value = resolve(name, allowBare: allowBare) else { return nil }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func set(_ name: String, value: String) throws {
        try validate(name: name)
        var aliases = load()
        aliases[normalize(name)] = value
        try save(aliases)
    }

    @discardableResult
    static func remove(_ name: String) throws -> Bool {
        var aliases = load()
        let removed = aliases.removeValue(forKey: normalize(name)) != nil
        try save(aliases)
        return removed
    }

    static func list() -> [String: String] {
        return load()
    }

    /// Alias names, for shell completion.
    static func names() -> [String] {
        return load().keys.sorted()
    }

    static func validate(name: String) throws {
        let key = normalize(name)
        guard !key.isEmpty else { throw ShareError.usage("alias name cannot be empty") }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ShareError.usage("alias name '\(key)' may only contain letters, digits, '-', '_' and '.'")
        }
    }

    private static func normalize(_ name: String) -> String {
        return name.hasPrefix("@") ? String(name.dropFirst()) : name
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: Paths.aliasesFile) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            Log.warn("ignoring malformed aliases file \(Paths.aliasesFile.path)")
            return [:]
        }
    }

    private static func save(_ aliases: [String: String]) throws {
        try Paths.ensureConfigDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(aliases)
        try data.write(to: Paths.aliasesFile, options: .atomic)
    }
}
