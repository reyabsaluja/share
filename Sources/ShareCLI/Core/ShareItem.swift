import Foundation

/// Something the user asked to share, before any packaging.
enum ShareItem: Equatable {
    case file(URL)
    case directory(URL)
    case url(URL)
    case text(String)

    /// Passes the item through without packaging (used by `--no-zip`).
    func toPrepared() -> PreparedShareItem {
        switch self {
        case .file(let url):
            return PreparedShareItem(kind: .file, originalDescription: url.path, value: .file(url), packaged: false, temporary: false, sizeBytes: Packager.fileSize(url))
        case .directory(let url):
            return PreparedShareItem(kind: .file, originalDescription: url.path, value: .file(url), packaged: false, temporary: false, sizeBytes: nil)
        case .url(let url):
            return PreparedShareItem(kind: .url, originalDescription: url.absoluteString, value: .url(url), packaged: false, temporary: false, sizeBytes: nil)
        case .text(let text):
            return PreparedShareItem(kind: .text, originalDescription: String(text.prefix(50)), value: .text(text), packaged: false, temporary: false, sizeBytes: Int64(text.utf8.count))
        }
    }

    var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .file(let url), .directory(let url): return url.lastPathComponent
        case .url(let url): return url.absoluteString
        case .text(let text): return String(text.prefix(60))
        }
    }
}

/// An item ready to hand to a backend.
struct PreparedShareItem {
    enum Kind: String, Encodable {
        case file
        case url
        case text
    }

    let kind: Kind
    let originalDescription: String
    let value: PreparedValue
    let packaged: Bool
    let temporary: Bool
    let sizeBytes: Int64?

    var displayName: String {
        switch value {
        case .file(let url): return url.lastPathComponent
        case .url(let url): return url.absoluteString
        case .text(let text): return String(text.prefix(60))
        }
    }

    var fileURL: URL? {
        if case .file(let url) = value { return url }
        return nil
    }

    var sizeDescription: String {
        if let size = sizeBytes { return HumanReadable.fileSize(size) }
        if let url = fileURL, let size = Packager.fileSize(url) { return HumanReadable.fileSize(size) }
        return ""
    }
}

enum PreparedValue {
    case file(URL)
    case url(URL)
    case text(String)
}
