import Foundation

enum HumanReadable {
    static func fileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }

    static func fileSizeAt(_ path: String) -> String? {
        guard let size = sizeOfFile(atPath: path) else { return nil }
        return fileSize(size)
    }

    static func sizeOfFile(atPath path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        if let size = attrs[.size] as? Int64 { return size }
        if let size = attrs[.size] as? Int { return Int64(size) }
        if let size = attrs[.size] as? NSNumber { return size.int64Value }
        return nil
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds) % 60
        return "\(minutes)m \(remainder)s"
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        let word = n == 1 ? singular : (plural ?? singular + "s")
        return "\(n) \(word)"
    }
}
