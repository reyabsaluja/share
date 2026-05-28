import Foundation

enum Color {
    static var enabled: Bool = {
        isatty(fileno(stderr)) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }()

    static func dim(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[2m\(text)\u{1B}[0m"
    }

    static func bold(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[1m\(text)\u{1B}[0m"
    }

    static func green(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[32m\(text)\u{1B}[0m"
    }

    static func red(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[31m\(text)\u{1B}[0m"
    }

    static func yellow(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[33m\(text)\u{1B}[0m"
    }

    static func cyan(_ text: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[36m\(text)\u{1B}[0m"
    }
}
