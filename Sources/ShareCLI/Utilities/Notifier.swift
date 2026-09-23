import Foundation

/// Posts a macOS user notification via osascript. Failures are silent by design.
enum Notifier {
    static func send(title: String, message: String) {
        let script = """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv)
        end run
        """
        Subprocess.run("/usr/bin/osascript", arguments: ["-e", script, title, message])
    }

    /// Notify only when the user opted in via config.
    static func sendIfEnabled(title: String = "share", message: String) {
        guard ShareConfig.current.notify == true else { return }
        send(title: title, message: message)
    }
}
