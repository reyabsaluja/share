import AppKit
import ArgumentParser
import Foundation

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Serve a file on your local network with a scannable QR code (no AirDrop needed).",
        discussion: """
        Starts a small HTTP server on this Mac and prints a link (and QR code) that any phone,
        tablet or laptop on the same Wi-Fi can open to download the file. Directories and multiple
        items are zipped first. The link uses a random token, nothing is uploaded anywhere, and the
        server stops on Ctrl-C, after --timeout, or after the first download with --once.
        """,
        aliases: ["link", "http"]
    )

    @Argument(help: "File or directory to serve. Defaults to the current directory.")
    var items: [String] = []

    @OptionGroup var output: OutputOptions
    @OptionGroup var packaging: PackagingOptions

    @Option(name: [.short, .long], help: "Port to listen on (default: config 'servePort', else a random free port).")
    var port: Int?

    @Flag(name: .long, help: "Stop after the first completed download.")
    var once = false

    @Option(name: .long, help: "Stop after this many seconds (default 600; 0 = until Ctrl-C).")
    var timeout: Int = 600

    @Flag(name: .long, help: "Do not print the QR code.")
    var noQr = false

    @Flag(name: .long, help: "Do not copy the link to the clipboard.")
    var noCopy = false

    @Option(name: .long, help: "Advertise this host/IP in the link instead of the detected one.")
    var host: String?

    func run() throws {
        output.apply()

        let resolved = try InputResolver.resolve(items)
        guard resolved.allSatisfy({ if case .url = $0 { return false }; if case .text = $0 { return false }; return true }) else {
            throw ShareError.unsupported("serve needs files or directories", hint: "use 'share qr <url>' to share a link")
        }

        let options = packaging.prepareOptions(destination: "serve", output: output)
        let prepared = try Preparer.prepare(resolved, options: options)

        let effectivePort = port ?? ShareConfig.current.servePort
        if let p = effectivePort, p < 0 || p > 65535 { throw ShareError.usage("--port must be between 0 and 65535") }

        guard let fileURL = prepared.first?.fileURL, prepared.count == 1 else {
            throw ShareError.unsupported("serve can only offer one file at a time", hint: "put several items in one zip: share serve a.txt b.txt (they are bundled automatically)")
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            throw ShareError.unsupported("serve cannot offer a raw directory", hint: "drop --no-zip so it is zipped first")
        }

        let advertisedHost = host ?? NetworkInfo.primaryLanIPv4()
        if output.dryRun {
            let plannedPort = effectivePort.map(String.init) ?? "<random>"
            Runner.printDryRun(destination: "serve", items: prepared, json: output.json, details: [("url", "http://\(advertisedHost ?? "<lan-ip>"):\(plannedPort)/<token>/\(fileURL.lastPathComponent)")])
            return
        }
        guard let hostName = advertisedHost else {
            throw ShareError.backendUnavailable("no local network address found", hint: "connect to Wi-Fi or Ethernet, or pass --host")
        }

        Runner.announcePackaged(prepared)

        let server = try LocalHTTPServer(file: fileURL, token: LocalHTTPServer.randomToken())
        try server.start(port: effectivePort.map { UInt16($0) })

        let url = "http://\(hostName):\(server.port)\(server.path)"
        if !noCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
        }

        if output.json {
            print(JSONOutput.format([
                "ok": true,
                "destination": "serve",
                "url": url,
                "port": Int(server.port),
                "file": fileURL.path,
                "sizeBytes": server.fileSize,
                "copiedToClipboard": !noCopy,
            ] as [String: Any]))
            fflush(stdout)
        } else {
            print("")
            print("  " + Color.bold("Serving \(fileURL.lastPathComponent)") + " " + Color.dim("(\(HumanReadable.fileSize(server.fileSize)))"))
            print("  " + Color.cyan(Color.underline(url)) + (noCopy ? "" : Color.dim("  copied ✓")))
            if let bonjour = NetworkInfo.localHostname(), host == nil {
                print("  " + Color.dim("also: http://\(bonjour):\(server.port)\(server.path)"))
            }
            print("")
            if !noQr && isatty(STDOUT_FILENO) != 0, let code = try? QRRenderer.code(url) {
                print(QRRenderer.terminal(code, color: Color.enabled))
                print("")
            }
            let until = timeout > 0 ? " for \(HumanReadable.duration(Double(timeout)))" : ""
            Log.info(Color.dim("Waiting for downloads\(until)… (Ctrl-C to stop)"))
        }

        History.record(destination: "serve", recipient: nil, items: items.isEmpty ? ["."] : items, archivePath: prepared.first(where: \.packaged)?.fileURL?.path)

        // Wait for Ctrl-C, timeout, or the first download with --once.
        let done = DispatchSemaphore(value: 0)
        var stopReason = "stopped"

        server.onDownload = { download in
            if download.complete {
                Log.info(Color.green("  ↓ \(download.remote) downloaded \(fileURL.lastPathComponent)") + Color.dim(" (\(HumanReadable.fileSize(download.bytes)))"))
                Notifier.sendIfEnabled(message: "\(download.remote) downloaded \(fileURL.lastPathComponent)")
                if once {
                    stopReason = "first download complete"
                    done.signal()
                }
            } else {
                Log.info(Color.yellow("  ✕ \(download.remote) aborted after \(HumanReadable.fileSize(download.bytes))"))
            }
        }
        server.onFailure = { error in
            Log.error("server failed: \(error.localizedDescription)")
            stopReason = "error"
            done.signal()
        }

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        for source in [sigint, sigterm] {
            source.setEventHandler { stopReason = "stopped"; done.signal() }
            source.resume()
        }
        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout)) {
                stopReason = "timeout"
                done.signal()
            }
        }

        done.wait()
        server.stop()

        if !output.json {
            let downloads = HumanReadable.count(server.downloadCount, "download")
            Log.info(Color.dim("\(stopReason.capitalized), \(downloads)."))
        }
        if server.downloadCount > 0 {
            TempFiles.removeRegistered()
        }
    }
}
