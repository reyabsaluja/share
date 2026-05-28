import Foundation

enum ShareIgnore {
    static func loadPatterns(from directory: URL) -> [String] {
        let ignoreFile = directory.appendingPathComponent(".shareignore")
        guard let content = try? String(contentsOf: ignoreFile, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func shouldExclude(name: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if name == pattern { return true }
            if pattern.hasSuffix("/") && name == String(pattern.dropLast()) { return true }
            if pattern.hasPrefix("*.") {
                let ext = String(pattern.dropFirst(2))
                if name.hasSuffix(".\(ext)") { return true }
            }
        }
        return false
    }
}
