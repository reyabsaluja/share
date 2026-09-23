import Foundation

/// Interactive confirmation that works even when stdin is a pipe.
///
/// Questions are asked on `/dev/tty` so `cat notes.md | share email bob@x.com .`
/// can still confirm a warning. When no terminal is attached the answer is
/// `nil` and callers decide what the safe default is.
enum Prompt {
    /// Set by `--yes`. Every question is answered "yes" without asking.
    static var assumeYes = false

    /// Test hook: when set, questions are answered from this closure instead of the terminal.
    static var answerOverride: ((String) -> Bool?)?

    static var isInteractive: Bool {
        if answerOverride != nil { return true }
        guard let tty = fopen("/dev/tty", "r") else { return false }
        fclose(tty)
        return true
    }

    /// Ask a yes/no question. Returns `nil` when there is no terminal to ask on.
    static func confirm(_ question: String, defaultAnswer: Bool = false) -> Bool? {
        if assumeYes { return true }
        if let override = answerOverride { return override(question) }

        guard let tty = fopen("/dev/tty", "r+") else { return nil }
        defer { fclose(tty) }

        let suffix = defaultAnswer ? "[Y/n]" : "[y/N]"
        fputs("\(question) \(suffix) ", tty)
        fflush(tty)

        var buffer = [CChar](repeating: 0, count: 256)
        guard fgets(&buffer, Int32(buffer.count), tty) != nil else { return nil }
        let answer = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if answer.isEmpty { return defaultAnswer }
        return answer.hasPrefix("y")
    }

    /// Ask for a line of free text. Returns `nil` when there is no terminal.
    static func ask(_ question: String) -> String? {
        guard let tty = fopen("/dev/tty", "r+") else { return nil }
        defer { fclose(tty) }
        fputs(question, tty)
        fflush(tty)
        var buffer = [CChar](repeating: 0, count: 1024)
        guard fgets(&buffer, Int32(buffer.count), tty) != nil else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
