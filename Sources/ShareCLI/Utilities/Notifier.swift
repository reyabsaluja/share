import Foundation

enum Notifier {
    static func send(title: String, message: String) {
        let script = """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv)
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, title, message]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try? process.run()
    }
}
