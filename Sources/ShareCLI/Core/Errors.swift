import Foundation

/// Every failure the CLI can report to the user.
///
/// Each case maps to a stable exit code and a short machine-readable code that
/// is emitted in `--json` mode. See `docs/exit-codes.md`.
enum ShareError: Error, LocalizedError, CustomStringConvertible {
    case usage(String, hint: String? = nil)
    case inputNotFound(String)
    case invalidURL(String)
    case packagingFailed(String)
    case backendUnavailable(String, hint: String? = nil)
    case userCancelled
    case automationDenied(app: String)
    case unsupported(String, hint: String? = nil)
    case sharingFailed(String, hint: String? = nil)
    case timeout(String)
    case configError(String, hint: String? = nil)
    case refused(String, hint: String? = nil)

    var exitCode: Int32 {
        switch self {
        case .usage, .invalidURL: return 2
        case .inputNotFound: return 3
        case .packagingFailed: return 4
        case .backendUnavailable: return 5
        case .userCancelled: return 6
        case .automationDenied: return 7
        case .unsupported: return 8
        case .sharingFailed: return 9
        case .timeout: return 10
        case .configError: return 11
        case .refused: return 12
        }
    }

    /// Stable identifier used in JSON output.
    var code: String {
        switch self {
        case .usage: return "usage"
        case .invalidURL: return "invalid_url"
        case .inputNotFound: return "input_not_found"
        case .packagingFailed: return "packaging_failed"
        case .backendUnavailable: return "backend_unavailable"
        case .userCancelled: return "cancelled"
        case .automationDenied: return "automation_denied"
        case .unsupported: return "unsupported"
        case .sharingFailed: return "sharing_failed"
        case .timeout: return "timeout"
        case .configError: return "config_error"
        case .refused: return "refused"
        }
    }

    var description: String {
        switch self {
        case .usage(let msg, _): return msg
        case .inputNotFound(let path): return "no such file or directory: \(path)"
        case .invalidURL(let url): return "invalid URL: \(url)"
        case .packagingFailed(let msg): return "packaging failed: \(msg)"
        case .backendUnavailable(let msg, _): return msg
        case .userCancelled: return "cancelled"
        case .automationDenied(let app): return "\(app) automation was denied by macOS"
        case .unsupported(let msg, _): return msg
        case .sharingFailed(let msg, _): return msg
        case .timeout(let msg): return msg
        case .configError(let msg, _): return msg
        case .refused(let msg, _): return msg
        }
    }

    /// A one-line suggestion printed under the error, when there is something useful to say.
    var hint: String? {
        switch self {
        case .usage(_, let hint): return hint ?? "run 'share --help' for usage"
        case .inputNotFound: return "check the path, or quote it if it contains spaces"
        case .invalidURL: return "URLs must start with http://, https:// or mailto:"
        case .packagingFailed: return "run with --verbose for details, or 'share doctor' to check your setup"
        case .backendUnavailable(_, let hint): return hint
        case .userCancelled: return nil
        case .automationDenied(let app):
            return "open System Settings → Privacy & Security → Automation and allow your terminal to control \(app)"
        case .unsupported(_, let hint): return hint
        case .sharingFailed(_, let hint): return hint
        case .timeout: return "try again, or pass --timeout to wait longer"
        case .configError(_, let hint): return hint ?? "run 'share config path' to locate the file"
        case .refused(_, let hint): return hint
        }
    }

    var errorDescription: String? { description }
}
