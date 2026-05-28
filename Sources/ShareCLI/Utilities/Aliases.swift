import Foundation

enum Aliases {
    private static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/share/aliases.json")
    }

    static func resolve(_ name: String) -> String? {
        guard name.hasPrefix("@") else { return nil }
        let key = String(name.dropFirst())
        let aliases = load()
        return aliases[key]
    }

    static func set(_ name: String, value: String) throws {
        var aliases = load()
        aliases[name] = value
        try save(aliases)
    }

    static func remove(_ name: String) throws {
        var aliases = load()
        aliases.removeValue(forKey: name)
        try save(aliases)
    }

    static func list() -> [String: String] {
        return load()
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func save(_ aliases: [String: String]) throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(aliases)
        try data.write(to: configURL)
    }
}
