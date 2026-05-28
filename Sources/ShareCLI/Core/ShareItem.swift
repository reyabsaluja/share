import Foundation

enum ShareItem {
    case file(URL)
    case directory(URL)
    case url(URL)
    case text(String)

    func toPrepared() -> PreparedShareItem {
        switch self {
        case .file(let url):
            return PreparedShareItem(kind: .file, originalDescription: url.path, value: .file(url), packaged: false, temporary: false, sizeBytes: nil)
        case .directory(let url):
            return PreparedShareItem(kind: .file, originalDescription: url.path, value: .file(url), packaged: false, temporary: false, sizeBytes: nil)
        case .url(let url):
            return PreparedShareItem(kind: .url, originalDescription: url.absoluteString, value: .url(url), packaged: false, temporary: false, sizeBytes: nil)
        case .text(let text):
            return PreparedShareItem(kind: .text, originalDescription: String(text.prefix(50)), value: .text(text), packaged: false, temporary: false, sizeBytes: Int64(text.utf8.count))
        }
    }
}

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
}

enum PreparedValue {
    case file(URL)
    case url(URL)
    case text(String)
}
