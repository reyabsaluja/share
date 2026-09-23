import Foundation

/// Turns command-line arguments into `ShareItem`s.
///
/// - No arguments means the current directory.
/// - `http://`, `https://` and `mailto:` arguments become URLs.
/// - `-` reads stdin as text.
/// - Everything else must exist on disk; `~` is expanded and relative paths resolve against the cwd.
struct InputResolver {
    static func resolve(_ arguments: [String]) throws -> [ShareItem] {
        var items: [ShareItem] = []

        let args = arguments.isEmpty ? ["."] : arguments

        for arg in args {
            if arg == "-" {
                guard let text = StdinReader.readAll() else {
                    throw ShareError.usage("'-' was given but stdin is empty")
                }
                items.append(.text(text))
                continue
            }
            if isURL(arg) {
                guard let url = URL(string: arg), url.host != nil || arg.lowercased().hasPrefix("mailto:") else {
                    throw ShareError.invalidURL(arg)
                }
                items.append(.url(url))
                continue
            }

            let standardized = expandPath(arg)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
                throw ShareError.inputNotFound(arg)
            }
            guard FileManager.default.isReadableFile(atPath: standardized.path) else {
                throw ShareError.refused("cannot read \(arg): permission denied")
            }
            items.append(isDir.boolValue ? .directory(standardized) : .file(standardized))
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
        guard !isURL(arg), arg != "-" else { return false }
        return FileManager.default.fileExists(atPath: expandPath(arg).path)
    }

    static func isURL(_ string: String) -> Bool {
        let lowered = string.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("mailto:")
    }
}
