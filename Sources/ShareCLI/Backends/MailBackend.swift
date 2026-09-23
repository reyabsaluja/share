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

/// Drives Mail.app via AppleScript. Creates a visible draft unless `send` is set.
final class MailBackend: SharingBackend {
    let name = "Mail.app (AppleScript)"
    let options: MailOptions

    init(options: MailOptions) {
        self.options = options
    }

    func share(_ items: [PreparedShareItem]) throws {
        let attachmentPaths = items.compactMap { $0.fileURL?.path }

        for path in attachmentPaths where !FileManager.default.fileExists(atPath: path) {
            throw ShareError.inputNotFound(path)
        }

        let subject = options.subject ?? defaultSubject(items: items)
        let body = Self.composeBody(options.body, items: items, hasAttachments: !attachmentPaths.isEmpty)
        let from = options.from ?? ShareConfig.current.from ?? ""

        var argv: [String] = [
            options.to,
            subject,
            body,
            options.send ? "true" : "false",
            from,
            options.cc ?? "",
            options.bcc ?? "",
        ]
        argv.append(contentsOf: attachmentPaths)

        try AppleScriptRunner.run(Self.script, arguments: argv, app: "Mail")
    }

    /// URLs and text items become part of the body since Mail cannot attach them.
    static func composeBody(_ explicit: String?, items: [PreparedShareItem], hasAttachments: Bool) -> String {
        var parts: [String] = []
        if let explicit = explicit, !explicit.isEmpty { parts.append(explicit) }
        let inline = items.compactMap { item -> String? in
            switch item.value {
            case .url(let url): return url.absoluteString
            case .text(let text): return text
            case .file: return nil
            }
        }
        if !inline.isEmpty { parts.append(inline.joined(separator: "\n")) }
        var body = parts.joined(separator: "\n\n")
        // Mail inserts attachments "after the last paragraph"; a trailing blank line keeps them off the text.
        if hasAttachments { body += "\n\n" }
        return body
    }

    private func defaultSubject(items: [PreparedShareItem]) -> String {
        let files = items.filter { $0.kind == .file }
        if files.count == 1, let item = files.first {
            let name = item.packaged ? (item.originalDescription as NSString).lastPathComponent : item.displayName
            return GitContext.smartSubject(itemName: name)
        }
        return GitContext.smartSubject()
    }

    static let script = """
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
                    set sender to fromAddress
                end if
                repeat with addr in my splitAddresses(toAddress)
                    make new to recipient at end of to recipients with properties {address:addr}
                end repeat
                if ccAddress is not "" then
                    repeat with addr in my splitAddresses(ccAddress)
                        make new cc recipient at end of cc recipients with properties {address:addr}
                    end repeat
                end if
                if bccAddress is not "" then
                    repeat with addr in my splitAddresses(bccAddress)
                        make new bcc recipient at end of bcc recipients with properties {address:addr}
                    end repeat
                end if
                if (count of argv) > 7 then
                    set attachmentPaths to items 8 thru -1 of argv
                    repeat with p in attachmentPaths
                        make new attachment with properties {file name:(POSIX file (p as text))} at after the last paragraph
                    end repeat
                end if
            end tell
            if shouldSend is "true" then
                delay 1
                send newMessage
            else
                activate
            end if
        end tell
    end run

    on splitAddresses(addressList)
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to ","
        set parts to text items of addressList
        set AppleScript's text item delimiters to oldDelimiters
        set trimmed to {}
        repeat with part in parts
            set t to part as text
            repeat while t starts with " "
                set t to text 2 thru -1 of t
            end repeat
            repeat while t ends with " "
                set t to text 1 thru -2 of t
            end repeat
            if t is not "" then set end of trimmed to t
        end repeat
        return trimmed
    end splitAddresses
    """
}
