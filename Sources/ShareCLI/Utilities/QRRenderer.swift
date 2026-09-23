import AppKit
import CoreImage
import Foundation

/// Generates QR codes as PNG data or as a terminal-renderable module grid.
enum QRRenderer {
    struct Code {
        /// Row-major grid of modules; `true` is a dark module. Includes a quiet zone.
        let modules: [[Bool]]
        var size: Int { modules.count }
    }

    enum CorrectionLevel: String {
        case low = "L", medium = "M", quartile = "Q", high = "H"
    }

    static func generate(_ text: String, correction: CorrectionLevel = .medium) throws -> CIImage {
        guard let data = text.data(using: .utf8) else {
            throw ShareError.packagingFailed("cannot encode text as UTF-8")
        }
        guard data.count <= 2900 else {
            throw ShareError.unsupported("text is too long for a QR code (\(data.count) bytes, max ~2900)", hint: "share a link instead: 'share serve <file>' prints a scannable URL")
        }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw ShareError.backendUnavailable("QR code generation is unavailable")
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else {
            throw ShareError.packagingFailed("failed to generate QR code")
        }
        return image
    }

    static func png(_ text: String, scale: CGFloat = 10, correction: CorrectionLevel = .medium) throws -> Data {
        let image = try generate(text, correction: correction).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: image)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ShareError.packagingFailed("failed to render QR image")
        }
        return png
    }

    /// Samples the generator output one module per pixel.
    static func code(_ text: String, correction: CorrectionLevel = .medium) throws -> Code {
        let image = try generate(text, correction: correction)
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ShareError.packagingFailed("failed to rasterize QR code")
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ShareError.packagingFailed("failed to read QR pixels")
        }
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rows: [[Bool]] = []
        for y in 0..<height {
            // CoreGraphics rows are bottom-up; QR codes are symmetric enough that order does not
            // matter for scanning, but keep the natural top-down orientation anyway.
            let row = (0..<width).map { x in pixels[(height - 1 - y) * width + x] < 128 }
            rows.append(row)
        }
        return Code(modules: rows)
    }

    /// Renders the code for a terminal using half-block characters: two module rows per text line.
    /// When `color` is set, explicit black-on-white ANSI colors make it scannable on any theme.
    static func terminal(_ code: Code, color: Bool, quietZone: Int = 2) -> String {
        let size = code.size
        let total = size + quietZone * 2
        func dark(_ x: Int, _ y: Int) -> Bool {
            let mx = x - quietZone, my = y - quietZone
            guard mx >= 0, my >= 0, mx < size, my < size else { return false }
            return code.modules[my][mx]
        }

        var lines: [String] = []
        var y = 0
        while y < total {
            var line = ""
            for x in 0..<total {
                let top = dark(x, y)
                let bottom = y + 1 < total ? dark(x, y + 1) : false
                switch (top, bottom) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                case (false, false): line += " "
                }
            }
            lines.append(color ? "\u{1B}[30;107m\(line)\u{1B}[0m" : line)
            y += 2
        }
        return lines.joined(separator: "\n")
    }
}
