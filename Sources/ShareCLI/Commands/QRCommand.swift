import ArgumentParser
import AppKit
import CoreImage
import Foundation

struct QRCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "qr",
        abstract: "Generate a QR code from text or URL."
    )

    @Argument(help: "Text or URL to encode.")
    var content: [String] = []

    @Option(name: .shortAndLong, help: "Save QR image to path.")
    var output: String?

    @Flag(name: .long, help: "Copy QR image to clipboard.")
    var copy = false

    @Flag(name: .long, help: "Open QR image in Preview.")
    var open = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    func run() throws {
        Log.quiet = quiet

        let text: String
        if !content.isEmpty {
            text = content.joined(separator: " ")
        } else if let piped = StdinReader.readIfPiped() {
            text = piped.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ShareError.usage("Provide text or URL to encode as QR")
        }

        guard let data = text.data(using: .utf8) else {
            throw ShareError.packagingFailed("Cannot encode text")
        }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw ShareError.backendUnavailable("QR code generation unavailable")
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            throw ShareError.packagingFailed("Failed to generate QR code")
        }

        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ShareError.packagingFailed("Failed to render QR image")
        }

        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try pngData.write(to: url)
            if !quiet { Log.info("Saved: \(outputPath)") }
        } else if copy || (!self.open && output == nil) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(pngData, forType: .png)
            if !quiet { Log.info("QR code copied to clipboard ✓") }
        }

        if self.open {
            let tmpPath = Packager.tempDirectory().appendingPathComponent("share-qr-\(DateSlug.current()).png")
            try pngData.write(to: tmpPath)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [tmpPath.path]
            try process.run()
            process.waitUntilExit()
        }
    }
}
