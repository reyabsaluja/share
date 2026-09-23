import Foundation

/// Machine-readable output for `--json`. Always printed to stdout, one object per run.
struct JSONOutput {
    /// Set at startup when `--json` is anywhere on the command line, so error paths can respond in kind.
    static var enabled = false

    static func success(destination: String, backend: String, items: [PreparedShareItem], openedNativeUI: Bool, extra: [String: Any] = [:]) -> String {
        var result: [String: Any] = [
            "ok": true,
            "destination": destination,
            "backend": backend,
            "items": items.map(describe),
            "openedNativeUI": openedNativeUI,
        ]
        for (key, value) in extra { result[key] = value }
        return format(result)
    }

    static func dryRun(destination: String, items: [PreparedShareItem], extra: [String: Any] = [:]) -> String {
        var result: [String: Any] = [
            "ok": true,
            "dryRun": true,
            "destination": destination,
            "items": items.map(describe),
        ]
        for (key, value) in extra { result[key] = value }
        return format(result)
    }

    static func error(_ error: ShareError) -> String {
        var payload: [String: Any] = [
            "code": error.code,
            "message": error.description,
            "exitCode": Int(error.exitCode),
        ]
        if let hint = error.hint { payload["hint"] = hint }
        return format(["ok": false, "error": payload])
    }

    static func error(code: String, message: String, exitCode: Int32 = 1) -> String {
        return format(["ok": false, "error": ["code": code, "message": message, "exitCode": Int(exitCode)] as [String: Any]])
    }

    static func describe(_ item: PreparedShareItem) -> [String: Any] {
        var dict: [String: Any] = [
            "kind": item.kind.rawValue,
            "original": item.originalDescription,
            "packaged": item.packaged,
            "temporary": item.temporary,
        ]
        if let size = item.sizeBytes { dict["sizeBytes"] = size }
        switch item.value {
        case .file(let url): dict["path"] = url.path
        case .url(let url): dict["url"] = url.absoluteString
        case .text(let text): dict["text"] = text
        }
        return dict
    }

    static func format(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
