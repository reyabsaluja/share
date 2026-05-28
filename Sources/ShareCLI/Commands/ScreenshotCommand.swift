import ArgumentParser
import AppKit
import Foundation

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Take a screenshot and share it.",
        aliases: ["ss", "snap"]
    )

    @Argument(help: "Recipient (email/phone/@alias). If omitted, copies to clipboard.")
    var recipient: String?

    @Flag(name: [.short, .long], help: "Capture a selection instead of full screen.")
    var selection = false

    @Flag(name: [.short, .long], help: "Capture a specific window.")
    var window = false

    @Option(name: .long, help: "Delay in seconds before capture.")
    var delay: Int?

    @Flag(name: .long, help: "Don't delete the screenshot after sharing.")
    var keep = false

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    @Flag(name: .long, help: "Send immediately (for messages).")
    var send = false

    @Option(name: .long, help: "Email subject.")
    var subject: String?

    func run() throws {
        Log.quiet = quiet

        let tmpPath = Packager.tempDirectory()
            .appendingPathComponent("share-screenshot-\(DateSlug.current()).png")

        if dryRun {
            print("Would capture screenshot → \(tmpPath.lastPathComponent)")
            if let r = recipient { print("Would share to: \(r)") }
            else { print("Would copy to clipboard") }
            return
        }

        var args: [String] = []
        if selection {
            args.append("-i")
        } else if window {
            args.append("-iW")
        }
        if let d = delay {
            args.append(contentsOf: ["-T", "\(d)"])
        }
        args.append(tmpPath.path)

        if !quiet { Log.info("Take your screenshot…") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tmpPath.path) else {
            throw ShareError.userCancelled
        }

        if !quiet {
            let size = HumanReadable.fileSizeAt(tmpPath.path) ?? "?"
            Log.info("Captured (\(size))")
        }

        guard let recipient = recipient else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let image = NSImage(contentsOf: tmpPath)
            if let img = image {
                pasteboard.writeObjects([img])
            }
            if !quiet { Log.info(Color.green("Copied to clipboard ✓")) }
            if !keep { try? FileManager.default.removeItem(at: tmpPath) }
            return
        }

        let resolvedRecipient = Aliases.resolve(recipient) ?? recipient

        if let destination = SmartRouter.detect(resolvedRecipient) {
            let items = try Packager.packageIfNeeded(
                items: [.file(tmpPath)],
                archiveName: nil,
                keepTemp: keep,
                verbose: false
            )

            switch destination {
            case .email(let address):
                if !quiet { Log.info("Drafting email to \(address)…") }
                let options = MailOptions(
                    to: address,
                    subject: subject ?? "Screenshot \(DateSlug.current())",
                    send: false
                )
                let backend = MailBackend(options: options)
                try backend.share(items)

            case .messages(let phone):
                if !quiet {
                    if send { Log.info("Sending to \(phone)…") }
                    else { Log.info("Opening Messages to \(phone)…") }
                }
                let options = MessagesOptions(recipient: phone, text: nil, send: send)
                let backend = MessagesBackend(options: options)
                try backend.share(items)

            case .airdrop:
                if !quiet { Log.info("Opening AirDrop…") }
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let backend = AirDropBackend()
                try backend.share(items)
            }
        } else {
            if !quiet { Log.info("Opening AirDrop…") }
            let items = [PreparedShareItem(kind: .file, originalDescription: tmpPath.path, value: .file(tmpPath), packaged: false, temporary: true, sizeBytes: nil)]
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let backend = AirDropBackend()
            try backend.share(items)
        }

        if !keep { try? FileManager.default.removeItem(at: tmpPath) }

        History.record(destination: "screenshot", recipient: resolvedRecipient, items: [], archivePath: tmpPath.path)
    }
}
