import Foundation

final class ShortcutsBackend: SharingBackend {
    let name = "Shortcuts.app"
    let shortcutName: String
    let outputPath: String?

    init(shortcutName: String, outputPath: String? = nil) {
        self.shortcutName = shortcutName
        self.outputPath = outputPath
    }

    func share(_ items: [PreparedShareItem]) throws {
        let inputPaths: [String] = items.compactMap { item in
            if case .file(let url) = item.value { return url.path }
            return nil
        }

        guard !inputPaths.isEmpty else {
            throw ShareError.unsupported("Shortcuts backend requires file inputs")
        }

        for inputPath in inputPaths {
            var arguments = ["run", shortcutName, "-i", inputPath]
            if let output = outputPath {
                arguments.append(contentsOf: ["-o", output])
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"
                throw ShareError.packagingFailed("shortcuts run failed: \(errorMsg)")
            }
        }
    }

    static func listShortcuts() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}
