import AppKit
import Foundation

struct MessagesOptions {
    var recipient: String
    var text: String?
    var send: Bool = false
    /// Use the SMS account (iPhone relay) instead of iMessage.
    var sms: Bool = false
}

/// Messages.app integration.
///
/// - `--send`: AppleScript sends the text and each file to the recipient immediately.
/// - default (draft): opens the conversation with the text pre-filled via the `sms:` URL
///   scheme; files are placed on the clipboard so a single ⌘V attaches them. Messages has no
///   scripting command for composing an unsent message, so this is the closest safe equivalent.
final class MessagesBackend: SharingBackend {
    let name = "Messages.app"
    let options: MessagesOptions

    init(options: MessagesOptions) {
        self.options = options
    }

    func share(_ items: [PreparedShareItem]) throws {
        let files = items.compactMap(\.fileURL)
        let inlineText = items.compactMap { item -> String? in
            switch item.value {
            case .url(let url): return url.absoluteString
            case .text(let text): return text
            case .file: return nil
            }
        }
        var messageParts: [String] = []
        if let text = options.text, !text.isEmpty { messageParts.append(text) }
        messageParts.append(contentsOf: inlineText)
        let messageText = messageParts.joined(separator: "\n")

        if options.send {
            try send(text: messageText, files: files)
        } else {
            try draft(text: messageText, files: files)
        }
    }

    // MARK: - Send

    private func send(text: String, files: [URL]) throws {
        guard !text.isEmpty || !files.isEmpty else {
            throw ShareError.usage("nothing to send: provide text or files")
        }
        let serviceType = (options.sms || ShareConfig.current.sms == true) ? "SMS" : "iMessage"
        var argv = [options.recipient, text, serviceType]
        argv.append(contentsOf: files.map(\.path))
        try AppleScriptRunner.run(Self.sendScript, arguments: argv, app: "Messages")
    }

    static let sendScript = """
    on run argv
        set recipientID to item 1 of argv
        set messageBody to item 2 of argv
        set serviceKind to item 3 of argv
        set filePaths to {}
        if (count of argv) > 3 then set filePaths to items 4 thru -1 of argv

        tell application "Messages"
            if serviceKind is "SMS" then
                set targetAccount to 1st account whose service type = SMS
            else
                set targetAccount to 1st account whose service type = iMessage
            end if
            set targetParticipant to participant recipientID of targetAccount
            if messageBody is not "" then
                send messageBody to targetParticipant
            end if
            repeat with fp in filePaths
                send (POSIX file (fp as text)) to targetParticipant
            end repeat
        end tell
    end run
    """

    // MARK: - Draft

    /// Builds `sms:<recipient>&body=<text>`, the form Messages.app understands for pre-filled drafts.
    static func draftURL(recipient: String, text: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "+@.-_")
        guard let handle = recipient.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var url = "sms:" + handle
        if !text.isEmpty {
            var bodyAllowed = CharacterSet.alphanumerics
            bodyAllowed.insert(charactersIn: "-._~")
            guard let body = text.addingPercentEncoding(withAllowedCharacters: bodyAllowed) else { return nil }
            url += "&body=" + body
        }
        return url
    }

    private func draft(text: String, files: [URL]) throws {
        guard let urlString = Self.draftURL(recipient: options.recipient, text: text) else {
            throw ShareError.usage("could not build a Messages URL for \(options.recipient)")
        }

        if !files.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(files as [NSURL])
        }

        let result = Subprocess.run("/usr/bin/open", arguments: [urlString])
        guard result.status == 0 else {
            throw ShareError.backendUnavailable("could not open Messages", hint: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if !files.isEmpty && !Log.quiet {
            let what = files.count == 1 ? files[0].lastPathComponent : HumanReadable.count(files.count, "file")
            Log.info("\(what) copied to clipboard — press ⌘V in Messages to attach, or use --send")
        }
    }
}
