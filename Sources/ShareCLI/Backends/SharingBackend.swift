import Foundation

/// A destination that can receive prepared items.
protocol SharingBackend {
    var name: String { get }
    func share(_ items: [PreparedShareItem]) throws
}

/// Shared helpers for AppleScript-driven backends.
enum AppleScriptRunner {
    /// Runs an AppleScript with arguments, translating macOS automation refusals into `ShareError`.
    static func run(_ script: String, arguments: [String], app: String) throws {
        let result = Subprocess.run("/usr/bin/osascript", arguments: ["-e", script] + arguments)
        guard result.status != 0 else { return }

        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAutomationDenied(message) {
            throw ShareError.automationDenied(app: app)
        }
        if message.contains("-1728") || message.lowercased().contains("can’t get") || message.lowercased().contains("can't get") {
            throw ShareError.sharingFailed(
                "\(app) could not find the recipient",
                hint: "for Messages, the recipient must already be reachable via iMessage; try the full number with country code"
            )
        }
        if message.contains("-600") || message.lowercased().contains("isn’t running") {
            throw ShareError.backendUnavailable("\(app) is not available", hint: "open \(app) once so macOS can launch it for automation")
        }
        throw ShareError.sharingFailed("\(app) automation failed: \(message.isEmpty ? "exit \(result.status)" : message)")
    }

    static func isAutomationDenied(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("-1743") || lower.contains("not authorized") || lower.contains("not allowed")
            || lower.contains("not permitted") || lower.contains("-10004")
    }
}
