import Foundation

/// ANSI color helpers.
///
/// Colors are enabled only when both stdout and stderr are terminals, the
/// `NO_COLOR` convention (https://no-color.org) is respected, `TERM=dumb`
/// disables them, `CLICOLOR_FORCE` forces them, and `--color`/`--no-color`
/// or the `color` config key override everything.
enum Color {
    enum Mode { case auto, always, never }

    static var mode: Mode = .auto

    static var enabled: Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .auto: return autoDetected
        }
    }

    private static let autoDetected: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil { return false }
        if let force = env["CLICOLOR_FORCE"], force != "0" { return true }
        if env["TERM"] == "dumb" { return false }
        return isatty(STDOUT_FILENO) != 0 && isatty(STDERR_FILENO) != 0
    }()

    static func dim(_ text: String) -> String { wrap(text, "2") }
    static func bold(_ text: String) -> String { wrap(text, "1") }
    static func green(_ text: String) -> String { wrap(text, "32") }
    static func red(_ text: String) -> String { wrap(text, "31") }
    static func yellow(_ text: String) -> String { wrap(text, "33") }
    static func cyan(_ text: String) -> String { wrap(text, "36") }
    static func underline(_ text: String) -> String { wrap(text, "4") }

    private static func wrap(_ text: String, _ code: String) -> String {
        guard enabled else { return text }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}
