import Foundation

enum Log {
    static var verbose = false
    static var quiet = false

    static func info(_ message: String) {
        guard !quiet else { return }
        fputs("\(message)\n", stderr)
    }

    static func debug(_ message: String) {
        guard verbose else { return }
        fputs(Color.dim(message) + "\n", stderr)
    }

    static func error(_ message: String) {
        fputs(Color.red("share: \(message)") + "\n", stderr)
    }

    static func hint(_ message: String) {
        fputs(Color.dim("hint: \(message)") + "\n", stderr)
    }

    static func success(_ message: String) {
        guard !quiet else { return }
        fputs(Color.green(message) + "\n", stderr)
    }
}
