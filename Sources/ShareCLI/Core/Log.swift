import Foundation

/// All human-facing status output goes to stderr so stdout stays clean for
/// machine-readable results (`--json`, paths, generated scripts).
enum Log {
    static var verbose = false
    static var quiet = false

    /// Progress and status lines. Suppressed by `--quiet`.
    static func info(_ message: String) {
        guard !quiet else { return }
        write(message)
    }

    /// Extra detail. Only shown with `--verbose`.
    static func debug(_ message: String) {
        guard verbose else { return }
        write(Color.dim(message))
    }

    /// Non-fatal problems the user should know about. Always shown.
    static func warn(_ message: String) {
        write(Color.yellow("warning: \(message)"))
    }

    /// Fatal problems. Always shown.
    static func error(_ message: String) {
        write(Color.red("share: \(message)"))
    }

    static func hint(_ message: String) {
        write(Color.dim("hint: \(message)"))
    }

    static func success(_ message: String) {
        guard !quiet else { return }
        write(Color.green(message))
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
