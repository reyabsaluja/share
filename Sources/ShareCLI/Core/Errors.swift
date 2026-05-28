import Foundation

enum ShareError: Error, LocalizedError, CustomStringConvertible {
    case usage(String)
    case inputNotFound(String)
    case invalidURL(String)
    case packagingFailed(String)
    case backendUnavailable(String)
    case automationDenied(String)
    case unsupported(String)
    case userCancelled

    var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .inputNotFound: return 3
        case .packagingFailed: return 4
        case .backendUnavailable: return 5
        case .userCancelled: return 6
        case .automationDenied: return 7
        case .unsupported: return 8
        case .invalidURL: return 2
        }
    }

    var description: String {
        switch self {
        case .usage(let msg): return msg
        case .inputNotFound(let path): return "no such file or directory: \(path)"
        case .invalidURL(let url): return "invalid URL: \(url)"
        case .packagingFailed(let msg): return "packaging failed: \(msg)"
        case .backendUnavailable(let msg): return msg
        case .automationDenied(let msg): return msg
        case .unsupported(let msg): return msg
        case .userCancelled: return "cancelled by user"
        }
    }

    var errorDescription: String? { description }
}
