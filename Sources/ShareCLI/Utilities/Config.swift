import Foundation

struct ShareConfig: Codable {
    var defaultSmart: Bool?
    var defaultFrom: String?
    var defaultSubjectTemplate: String?
    var autoNotify: Bool?
    var autoCopyZip: Bool?
    var color: Bool?

    static let empty = ShareConfig()

    static func load() -> ShareConfig {
        let paths = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".share.json"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/share/config.json"),
        ]

        for path in paths {
            if let data = try? Data(contentsOf: path),
               let config = try? JSONDecoder().decode(ShareConfig.self, from: data) {
                return config
            }
        }
        return .empty
    }
}
