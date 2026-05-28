import ArgumentParser
import Foundation

struct PreviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "Preview what will be shared without sending.",
        aliases: ["ls", "info"]
    )

    @Argument(help: "Files, directories, or URLs. Defaults to current directory.")
    var items: [String] = []

    @Flag(name: .long, help: "Show what --smart would exclude.")
    var smart = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        let resolved = try InputResolver.resolve(items)

        if json {
            var result: [[String: Any]] = []
            for item in resolved {
                var dict: [String: Any] = ["type": itemType(item)]
                switch item {
                case .file(let url):
                    dict["path"] = url.path
                    dict["name"] = url.lastPathComponent
                    dict["size"] = HumanReadable.fileSizeAt(url.path) ?? "unknown"
                case .directory(let url):
                    dict["path"] = url.path
                    dict["name"] = url.lastPathComponent
                    dict["size"] = directorySize(url)
                    dict["project"] = "\(ProjectDetector.detect(at: url))"
                case .url(let url):
                    dict["url"] = url.absoluteString
                case .text(let text):
                    dict["text"] = String(text.prefix(100))
                    dict["length"] = text.count
                }
                result.append(dict)
            }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        let cwd = FileManager.default.currentDirectoryPath
        let repoName = GitContext.repoName()
        let branch = GitContext.branchName()
        let projectType = ProjectDetector.detect()

        print("")
        if let name = repoName {
            var header = "  " + Color.bold(name)
            if let b = branch, b != "main" && b != "master" { header += " " + Color.cyan("(\(b))") }
            if projectType != .unknown { header += " " + Color.dim("[\(projectType)]") }
            print(header)
        } else {
            print("  " + Color.bold(URL(fileURLWithPath: cwd).lastPathComponent))
        }
        print("")

        for item in resolved {
            switch item {
            case .file(let url):
                let size = HumanReadable.fileSizeAt(url.path) ?? "?"
                print("  " + Color.green("●") + " \(url.lastPathComponent)  " + Color.dim("(\(size))"))
            case .directory(let url):
                let size = directorySize(url)
                let fileCount = countFiles(url)
                print("  " + Color.cyan("●") + " \(url.lastPathComponent)/  " + Color.dim("(\(size), \(fileCount) files)"))

                if smart {
                    let excludes = ProjectDetector.excludes(for: projectType)
                    let wouldExclude = findExcludable(in: url, patterns: excludes)
                    if !wouldExclude.isEmpty {
                        print("     " + Color.dim("--smart would exclude:"))
                        for name in wouldExclude.prefix(8) {
                            print("       " + Color.red("✕") + " " + Color.dim(name))
                        }
                        if wouldExclude.count > 8 {
                            print("       " + Color.dim("… and \(wouldExclude.count - 8) more"))
                        }
                    }
                }

                let secrets = SecretsDetector.scan(directory: url)
                if !secrets.isEmpty {
                    print("     " + Color.yellow("⚠ sensitive files:"))
                    for s in secrets.prefix(5) {
                        print("       " + Color.yellow("!") + " \(s)")
                    }
                }

            case .url(let url):
                print("  " + Color.cyan("●") + " \(url.absoluteString)")
            case .text(let text):
                print("  " + Color.green("●") + " \"\(text.prefix(60))\"  " + Color.dim("(\(text.count) chars)"))
            }
        }

        print("")
        if resolved.contains(where: { if case .directory = $0 { return true }; return false }) {
            let archiveName = GitContext.smartArchiveName()
            print("  " + Color.dim("Archive: \(archiveName)-<timestamp>.zip"))
            if !smart {
                Log.hint("use --smart to exclude build artifacts")
            }
        }
        print("")
    }

    private func itemType(_ item: ShareItem) -> String {
        switch item {
        case .file: return "file"
        case .directory: return "directory"
        case .url: return "url"
        case .text: return "text"
        }
    }

    private func directorySize(_ url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sh", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\t").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }

    private func countFiles(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }

    private func findExcludable(in directory: URL, patterns: Set<String>) -> [String] {
        var found: [String] = []
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        for name in contents {
            if patterns.contains(name) {
                found.append(name)
            }
        }
        return found.sorted()
    }
}
