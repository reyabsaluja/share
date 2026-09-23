import AppKit
import ArgumentParser
import Foundation

struct QRCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "qr",
        abstract: "Show a QR code for text or a URL, right in the terminal.",
        discussion: """
        By default the code is printed in the terminal (scan it with your phone). Add --copy,
        --output or --open to get a PNG instead. When stdout is not a terminal, the PNG is
        copied to the clipboard.
        """
    )

    @Argument(help: "Text or URL to encode. Reads stdin when omitted.")
    var content: [String] = []

    @OptionGroup var output: OutputOptions

    @Option(name: [.short, .long], help: "Save the QR code as a PNG at this path.")
    var outputPath: String?

    @Flag(name: .long, help: "Copy the PNG to the clipboard.")
    var copy = false

    @Flag(name: .long, help: "Open the PNG in Preview.")
    var open = false

    @Flag(name: [.short, .long], help: "Print in the terminal (default when no other output is chosen).")
    var print = false

    @Option(name: .long, help: "Pixel size of each module in the PNG (default 10).")
    var scale: Int = 10

    @Option(name: .long, help: "Error correction level: L, M, Q or H (default M).")
    var correction: String = "M"

    func run() throws {
        output.apply()

        let text: String
        if !content.isEmpty {
            text = content.joined(separator: " ")
        } else if let piped = StdinReader.readIfPiped() {
            text = piped.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ShareError.usage("provide text or a URL to encode")
        }
        guard !text.isEmpty else { throw ShareError.usage("nothing to encode") }

        guard let level = QRRenderer.CorrectionLevel(rawValue: correction.uppercased()) else {
            throw ShareError.usage("--correction must be L, M, Q or H")
        }
        guard scale > 0 && scale <= 100 else { throw ShareError.usage("--scale must be between 1 and 100") }

        let wantsPNG = outputPath != nil || copy || open
        let printToTerminal = print || (!wantsPNG && isatty(STDOUT_FILENO) != 0)
        let copyToClipboard = copy || (!wantsPNG && !printToTerminal)

        if output.dryRun {
            var actions: [String] = []
            if printToTerminal { actions.append("print in terminal") }
            if copyToClipboard { actions.append("copy PNG to clipboard") }
            if let p = outputPath { actions.append("save to \(p)") }
            if open { actions.append("open in Preview") }
            Swift.print("Would encode \(text.count) characters and \(actions.joined(separator: ", "))")
            return
        }

        var result: [String: Any] = ["ok": true, "destination": "qr", "characters": text.count]

        if printToTerminal {
            let code = try QRRenderer.code(text, correction: level)
            Swift.print(QRRenderer.terminal(code, color: Color.enabled))
            Log.info(Color.dim(text.count > 60 ? String(text.prefix(60)) + "…" : text))
        }

        if wantsPNG || copyToClipboard {
            let png = try QRRenderer.png(text, scale: CGFloat(scale), correction: level)
            if let path = outputPath {
                let url = InputResolver.expandPath(path)
                try png.write(to: url)
                result["outputPath"] = url.path
                Log.info("Saved → \(url.path)")
            }
            if copyToClipboard {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(png, forType: .png)
                result["copiedToClipboard"] = true
                Log.success("QR code copied to clipboard ✓")
            }
            if open {
                let tmp = Packager.tempDirectory().appendingPathComponent("qr-\(DateSlug.current()).png")
                try png.write(to: tmp)
                Subprocess.run("/usr/bin/open", arguments: [tmp.path])
                result["opened"] = tmp.path
            }
        }

        if output.json {
            Swift.print(JSONOutput.format(result))
        }
    }
}
