import Foundation

struct MailOptions {
    var to: String
    var from: String?
    var cc: String?
    var bcc: String?
    var subject: String?
    var body: String?
    var send: Bool = false
}

final class MailBackend: SharingBackend {
    let name = "Mail.app (AppleScript)"
    let options: MailOptions

    init(options: MailOptions) {
        self.options = options
    }

    func share(_ items: [PreparedShareItem]) throws {
        let attachmentPaths: [String] = items.compactMap { item in
            if case .file(let url) = item.value { return url.path }
            return nil
        }

        let subject = options.subject ?? defaultSubject(items: items)
        let body = options.body ?? ""
        let shouldSend = options.send ? "true" : "false"

        var argv: [String] = [
            options.to,
            subject,
            body,
            shouldSend,
            options.from ?? "",
            options.cc ?? "",
            options.bcc ?? "",
        ]
        argv.append(contentsOf: attachmentPaths)

        let script = appleScript(hasCC: options.cc != nil, hasBCC: options.bcc != nil, hasFrom: options.from != nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + argv

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"

            if errorMsg.contains("not allowed") || errorMsg.contains("permission") {
                throw ShareError.automationDenied(
                    "Mail automation was denied by macOS.\nhint: Open System Settings → Privacy & Security → Automation and allow Terminal to control Mail."
                )
            }
            throw ShareError.packagingFailed("osascript failed: \(errorMsg)")
        }
    }

    private func defaultSubject(items: [PreparedShareItem]) -> String {
        if items.count == 1, let item = items.first {
            let name: String
            switch item.value {
            case .file(let url): name = url.lastPathComponent
            case .url(let url): name = url.absoluteString
            case .text: name = "text"
            }
            return "Shared: \(name)"
        }
        return "Shared files"
    }

    private func appleScript(hasCC: Bool, hasBCC: Bool, hasFrom: Bool) -> String {
        return """
        on run argv
            set toAddress to item 1 of argv
            set subjectText to item 2 of argv
            set bodyText to item 3 of argv
            set shouldSend to item 4 of argv
            set fromAddress to item 5 of argv
            set ccAddress to item 6 of argv
            set bccAddress to item 7 of argv

            tell application "Mail"
                set newMessage to make new outgoing message with properties {subject:subjectText, content:bodyText, visible:true}
                tell newMessage
                    if fromAddress is not "" then
                        set sender of newMessage to fromAddress
                    end if
                    make new to recipient at end of to recipients with properties {address:toAddress}
                    if ccAddress is not "" then
                        make new cc recipient at end of cc recipients with properties {address:ccAddress}
                    end if
                    if bccAddress is not "" then
                        make new bcc recipient at end of bcc recipients with properties {address:bccAddress}
                    end if
                    if (count of argv) > 7 then
                        set attachmentPaths to items 8 thru -1 of argv
                        repeat with p in attachmentPaths
                            make new attachment with properties {file name:POSIX file p} at after the last paragraph
                        end repeat
                    end if
                    if shouldSend is "true" then send
                end tell
                activate
            end tell
        end run
        """
    }
}
