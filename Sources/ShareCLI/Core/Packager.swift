import Foundation

struct Packager {
    static func packageIfNeeded(
        items: [ShareItem],
        archiveName: String?,
        keepTemp: Bool,
        verbose: Bool
    ) throws -> [PreparedShareItem] {
        var prepared: [PreparedShareItem] = []
        var directoriesToZip: [(URL, String)] = []
        var filesToStage: [URL] = []

        for item in items {
            switch item {
            case .file(let url):
                let size = fileSize(url)
                prepared.append(PreparedShareItem(
                    kind: .file,
                    originalDescription: url.path,
                    value: .file(url),
                    packaged: false,
                    temporary: false,
                    sizeBytes: size
                ))
            case .directory(let url):
                directoriesToZip.append((url, url.lastPathComponent))
            case .url(let url):
                prepared.append(PreparedShareItem(
                    kind: .url,
                    originalDescription: url.absoluteString,
                    value: .url(url),
                    packaged: false,
                    temporary: false,
                    sizeBytes: nil
                ))
            case .text(let text):
                prepared.append(PreparedShareItem(
                    kind: .text,
                    originalDescription: String(text.prefix(50)),
                    value: .text(text),
                    packaged: false,
                    temporary: false,
                    sizeBytes: Int64(text.utf8.count)
                ))
            }
        }

        if directoriesToZip.count == 1 && prepared.isEmpty {
            let (dirURL, dirName) = directoriesToZip[0]
            let name = archiveName ?? GitContext.repoName() ?? dirName
            let zipURL = try createZip(source: dirURL, name: name, verbose: verbose)
            let size = fileSize(zipURL)
            prepared.append(PreparedShareItem(
                kind: .file,
                originalDescription: dirURL.path,
                value: .file(zipURL),
                packaged: true,
                temporary: true,
                sizeBytes: size
            ))
        } else if !directoriesToZip.isEmpty {
            let stagingDir = tempDirectory().appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            for (dirURL, _) in directoriesToZip {
                let dest = stagingDir.appendingPathComponent(dirURL.lastPathComponent)
                try FileManager.default.copyItem(at: dirURL, to: dest)
            }

            for item in prepared where item.kind == .file {
                if case .file(let url) = item.value {
                    filesToStage.append(url)
                }
            }

            let name = archiveName ?? "share-bundle"
            let zipURL = try createZip(source: stagingDir, name: name, verbose: verbose)
            let size = fileSize(zipURL)

            prepared = prepared.filter { (item: PreparedShareItem) -> Bool in
                guard item.kind == .file else { return true }
                guard case .file(let u) = item.value else { return true }
                return !filesToStage.contains(u)
            }

            prepared.append(PreparedShareItem(
                kind: .file,
                originalDescription: "bundle",
                value: .file(zipURL),
                packaged: true,
                temporary: true,
                sizeBytes: size
            ))
        }

        return prepared
    }

    static func zipOnly(
        items: [ShareItem],
        archiveName: String?,
        outputPath: String?,
        verbose: Bool
    ) throws -> URL {
        let tempDir = tempDirectory()

        if items.count == 1, case .directory(let url) = items[0] {
            let name = archiveName ?? url.lastPathComponent
            if let output = outputPath {
                return try createZip(source: url, outputURL: URL(fileURLWithPath: output), verbose: verbose)
            }
            return try createZip(source: url, name: name, verbose: verbose)
        }

        if items.count == 1, case .file(let url) = items[0] {
            let name = archiveName ?? url.deletingPathExtension().lastPathComponent
            if let output = outputPath {
                return try createZip(source: url, outputURL: URL(fileURLWithPath: output), verbose: verbose)
            }
            return try createZip(source: url, name: name, verbose: verbose)
        }

        let stagingDir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for item in items {
            switch item {
            case .file(let url):
                let dest = stagingDir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: dest)
            case .directory(let url):
                let dest = stagingDir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: dest)
            case .url, .text:
                break
            }
        }

        let name = archiveName ?? "share-bundle"
        if let output = outputPath {
            return try createZip(source: stagingDir, outputURL: URL(fileURLWithPath: output), verbose: verbose)
        }
        return try createZip(source: stagingDir, name: name, verbose: verbose)
    }

    static func createZip(source: URL, name: String, verbose: Bool) throws -> URL {
        let slug = DateSlug.current()
        let zipName = "\(name)-\(slug).zip"
        let outputURL = tempDirectory().appendingPathComponent(zipName)
        return try createZip(source: source, outputURL: outputURL, verbose: verbose)
    }

    static func createZip(source: URL, outputURL: URL, verbose: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, outputURL.path]

        if verbose {
            Log.info("Packaging \(source.lastPathComponent) → \(outputURL.lastPathComponent)")
        }

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw ShareError.packagingFailed("ditto failed: \(errorMsg)")
        }

        return outputURL
    }

    static func tempDirectory() -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("share-cli")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }
}
