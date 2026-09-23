import Foundation

/// Runs a Shortcut via the `shortcuts` CLI. Files are passed with `-i`; URLs and text are piped on stdin.
final class ShortcutsBackend: SharingBackend {
    let name = "Shortcuts.app"
    let shortcutName: String
    let outputPath: String?

    init(shortcutName: String, outputPath: String? = nil) {
        self.shortcutName = shortcutName
        self.outputPath = outputPath
    }

    func share(_ items: [PreparedShareItem]) throws {
        guard !items.isEmpty else {
            throw ShareError.usage("nothing to pass to the shortcut")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts") else {
            throw ShareError.backendUnavailable("the shortcuts command-line tool is missing", hint: "it ships with macOS 12 and later")
        }

        for (index, item) in items.enumerated() {
            var arguments = ["run", shortcutName]
            var stdin: String?
            switch item.value {
            case .file(let url):
                arguments.append(contentsOf: ["-i", url.path])
            case .url(let url):
                stdin = url.absoluteString
            case .text(let text):
                stdin = text
            }
            if let output = outputPath {
                let target = items.count == 1 ? output : Self.indexedOutput(output, index: index)
                arguments.append(contentsOf: ["-o", target])
            }

            let result = Subprocess.run("/usr/bin/shortcuts", arguments: arguments, stdin: stdin)
            guard result.status == 0 else {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.lowercased().contains("not found") || message.lowercased().contains("couldn’t find") {
                    throw ShareError.inputNotFound("shortcut \"\(shortcutName)\"")
                }
                throw ShareError.sharingFailed("shortcut \"\(shortcutName)\" failed: \(message.isEmpty ? "exit \(result.status)" : message)")
            }
        }
    }

    static func indexedOutput(_ path: String, index: Int) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(stem)-\(index + 1)" : "\(stem)-\(index + 1).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(name).path
    }

    static func listShortcuts() throws -> [String] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts") else {
            throw ShareError.backendUnavailable("the shortcuts command-line tool is missing")
        }
        let result = Subprocess.run("/usr/bin/shortcuts", arguments: ["list"])
        guard result.status == 0 else {
            throw ShareError.backendUnavailable("could not list shortcuts", hint: "open Shortcuts.app once, then try again")
        }
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}
