import Foundation

struct JSONOutput {
    static func success(destination: String, backend: String, items: [PreparedShareItem], openedNativeUI: Bool) -> String {
        var itemDicts: [[String: Any]] = []
        for item in items {
            var dict: [String: Any] = [
                "kind": item.kind.rawValue,
                "originalPath": item.originalDescription,
                "packaged": item.packaged,
            ]
            if let size = item.sizeBytes {
                dict["sizeBytes"] = size
            }
            if case .file(let url) = item.value {
                dict["sharedPath"] = url.path
            }
            itemDicts.append(dict)
        }

        let result: [String: Any] = [
            "ok": true,
            "destination": destination,
            "backend": backend,
            "items": itemDicts,
            "openedNativeUI": openedNativeUI,
        ]

        return formatJSON(result)
    }

    static func error(code: String, message: String) -> String {
        let result: [String: Any] = [
            "ok": false,
            "error": [
                "code": code,
                "message": message,
            ] as [String: Any],
        ]
        return formatJSON(result)
    }

    private static func formatJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
