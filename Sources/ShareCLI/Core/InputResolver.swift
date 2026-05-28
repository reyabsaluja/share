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
                let expanded = NSString(string: arg).expandingTildeInPath
                let resolved: URL
                if expanded.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: expanded)
                } else {
                    resolved = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent(expanded)
                }
                let standardized = resolved.standardized

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

    static func isURL(_ string: String) -> Bool {
        let lowered = string.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("mailto:")
    }
}
