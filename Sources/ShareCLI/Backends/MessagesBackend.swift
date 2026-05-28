import Foundation

struct MessagesOptions {
    var recipient: String
    var text: String?
    var send: Bool = false
}

final class MessagesBackend: SharingBackend {
    let name = "Messages.app (AppleScript)"
    let options: MessagesOptions

    init(options: MessagesOptions) {
        self.options = options
    }

    func share(_ items: [PreparedShareItem]) throws {
        let hasFiles = items.contains { item in
            if case .file = item.value { return true }
            return false
        }

        let textParts: [String] = items.compactMap { item in
            switch item.value {
            case .url(let url): return url.absoluteString
            case .text(let text): return text
            case .file: return nil
            }
        }

        let messageText = options.text ?? textParts.joined(separator: "\n")

        if hasFiles {
            try shareWithFiles(items: items, messageText: messageText)
        } else {
            try shareTextOnly(messageText: messageText)
        }
    }

    private func shareTextOnly(messageText: String) throws {
        let script = """
        on run argv
            set recipientID to item 1 of argv
            set messageBody to item 2 of argv
            set shouldSend to item 3 of argv

            tell application "Messages"
                set targetBuddy to buddy recipientID of (service 1 whose service type is iMessage)
                if shouldSend is "true" then
                    send messageBody to targetBuddy
                else
                    activate
                end if
            end tell
        end run
        """

        let shouldSend = options.send ? "true" : "false"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, options.recipient, messageText, shouldSend]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"

            if errorMsg.contains("not allowed") || errorMsg.contains("permission") {
                throw ShareError.automationDenied(
                    "Messages automation was denied by macOS.\nhint: Open System Settings → Privacy & Security → Automation and allow Terminal to control Messages."
                )
            }
            throw ShareError.packagingFailed("osascript failed: \(errorMsg)")
        }
    }

    private func shareWithFiles(items: [PreparedShareItem], messageText: String) throws {
        let filePaths: [String] = items.compactMap { item in
            if case .file(let url) = item.value { return url.path }
            return nil
        }

        let script = """
        on run argv
            set recipientID to item 1 of argv
            set messageBody to item 2 of argv
            set shouldSend to item 3 of argv
            set filePaths to items 4 thru -1 of argv

            tell application "Messages"
                set targetBuddy to buddy recipientID of (service 1 whose service type is iMessage)
                if shouldSend is "true" then
                    if messageBody is not "" then
                        send messageBody to targetBuddy
                    end if
                    repeat with fp in filePaths
                        send POSIX file fp to targetBuddy
                    end repeat
                else
                    activate
                end if
            end tell
        end run
        """

        let shouldSend = options.send ? "true" : "false"
        var argv: [String] = ["-e", script, options.recipient, messageText, shouldSend]
        argv.append(contentsOf: filePaths)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = argv

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"

            if errorMsg.contains("not allowed") || errorMsg.contains("permission") {
                throw ShareError.automationDenied(
                    "Messages automation was denied by macOS.\nhint: Open System Settings → Privacy & Security → Automation and allow Terminal to control Messages."
                )
            }
            throw ShareError.packagingFailed("osascript failed: \(errorMsg)")
        }
    }
}
