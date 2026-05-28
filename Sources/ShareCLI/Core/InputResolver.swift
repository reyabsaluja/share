import Foundation

struct InputResolver {
    static func resolve(_ arguments: [String]) throws -> [ShareItem] {
        var items: [ShareItem] = []

        let args = arguments.isEmpty ? ["."] : arguments

        for arg in args {
            if isURL(arg) {
                guard let url = URL(string: arg) else {
                    throw ShareError.invalidURL(arg)
                }
                items.append(.url(url))
            } else {
                let standardized = expandPath(arg)

                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
                    throw ShareError.inputNotFound(arg)
                }

                if isDir.boolValue {
                    items.append(.directory(standardized))
                } else {
                    items.append(.file(standardized))
                }
            }
        }

        return items
    }

    static func expandPath(_ arg: String) -> URL {
        let expanded = NSString(string: arg).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardized
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).standardized
    }

    static func existsAsFile(_ arg: String) -> Bool {
        let url = expandPath(arg)
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func isURL(_ string: String) -> Bool {
        let lowered = string.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("mailto:")
    }
}
