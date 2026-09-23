import Foundation

/// Turns directories (and groups of items) into zip archives using `ditto`.
///
/// Archives are written to the scratch directory as `<name>-<timestamp>.zip` and
/// unpack to a single top-level folder named after the shared directory (or
/// `<name>` for bundles), with no AppleDouble `._` files or `__MACOSX` folders.
struct Packager {
    static let bundleName = "share-bundle"

    /// Prepares items for a backend: single directories become one zip; several
    /// directories (with any loose files) become one bundle zip; files, URLs and
    /// text pass through untouched.
    static func packageIfNeeded(items: [ShareItem], archiveName: String?, verbose: Bool) throws -> [PreparedShareItem] {
        var prepared: [PreparedShareItem] = []
        var directories: [URL] = []
        var looseFiles: [URL] = []

        for item in items {
            switch item {
            case .file(let url):
                looseFiles.append(url)
                prepared.append(PreparedShareItem(kind: .file, originalDescription: url.path, value: .file(url), packaged: false, temporary: false, sizeBytes: fileSize(url)))
            case .directory(let url):
                directories.append(url)
            case .url(let url):
                prepared.append(PreparedShareItem(kind: .url, originalDescription: url.absoluteString, value: .url(url), packaged: false, temporary: false, sizeBytes: nil))
            case .text(let text):
                prepared.append(PreparedShareItem(kind: .text, originalDescription: String(text.prefix(50)), value: .text(text), packaged: false, temporary: false, sizeBytes: Int64(text.utf8.count)))
            }
        }

        if directories.count == 1 && looseFiles.isEmpty {
            let dir = directories[0]
            let name = archiveName ?? GitContext.archiveName(for: dir)
            let zipURL = try createZip(source: dir, name: name, verbose: verbose)
            prepared.append(PreparedShareItem(kind: .file, originalDescription: dir.path, value: .file(zipURL), packaged: true, temporary: true, sizeBytes: fileSize(zipURL)))
        } else if !directories.isEmpty {
            let name = archiveName ?? bundleName
            let staging = try stageBundle(directories: directories, files: looseFiles, name: name)
            let zipURL = try createZip(source: staging, name: name, verbose: verbose)
            prepared.removeAll { item in
                if case .file = item.value, !item.packaged { return true }
                return false
            }
            prepared.append(PreparedShareItem(kind: .file, originalDescription: "bundle", value: .file(zipURL), packaged: true, temporary: true, sizeBytes: fileSize(zipURL)))
        }

        return prepared
    }

    /// Creates exactly one zip containing every file/directory item and returns its URL.
    /// `outputPath` may be a file path (used verbatim) or an existing directory (archive is placed inside).
    static func zipOnly(items: [ShareItem], archiveName: String?, outputPath: String?, overwrite: Bool = false, verbose: Bool) throws -> URL {
        let sources = items.compactMap { item -> URL? in
            switch item {
            case .file(let url), .directory(let url): return url
            case .url, .text: return nil
            }
        }
        guard !sources.isEmpty else {
            throw ShareError.usage("nothing to zip: provide at least one file or directory")
        }

        let name = archiveName ?? defaultArchiveName(for: items)
        let outputURL = try resolveOutput(outputPath, name: name, overwrite: overwrite)

        if sources.count == 1 {
            return try createZip(source: sources[0], outputURL: outputURL, verbose: verbose)
        }

        let directories = items.compactMap { if case .directory(let u) = $0 { return u }; return nil }
        let files = items.compactMap { if case .file(let u) = $0 { return u }; return nil }
        let staging = try stageBundle(directories: directories, files: files, name: name)
        return try createZip(source: staging, outputURL: outputURL, verbose: verbose)
    }

    /// The name a zip would get for these items (without timestamp or extension).
    static func defaultArchiveName(for items: [ShareItem]) -> String {
        if items.count == 1 {
            switch items[0] {
            case .file(let url): return url.deletingPathExtension().lastPathComponent
            case .directory(let url): return GitContext.archiveName(for: url)
            default: break
            }
        }
        return bundleName
    }

    /// Path a temp archive would be written to. Used for dry runs.
    static func plannedArchiveURL(name: String) -> URL {
        return tempDirectory().appendingPathComponent("\(name)-\(DateSlug.current()).zip")
    }

    static func createZip(source: URL, name: String, verbose: Bool) throws -> URL {
        let outputURL = plannedArchiveURL(name: name)
        return try createZip(source: source, outputURL: outputURL, verbose: verbose)
    }

    static func createZip(source: URL, outputURL: URL, verbose: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto") else {
            throw ShareError.backendUnavailable("/usr/bin/ditto is missing", hint: "ditto ships with macOS; reinstall the Command Line Tools if it is gone")
        }

        if verbose {
            Log.debug("packaging \(source.lastPathComponent) → \(outputURL.lastPathComponent)")
        }

        let start = Date()
        let result = Subprocess.run(
            "/usr/bin/ditto",
            arguments: ["-c", "-k", "--norsrc", "--keepParent", source.path, outputURL.path]
        )
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShareError.packagingFailed("ditto failed: \(message.isEmpty ? "exit \(result.status)" : message)")
        }
        if verbose {
            Log.debug("packaged in \(HumanReadable.duration(Date().timeIntervalSince(start)))")
        }
        if outputURL.path.hasPrefix(tempDirectory().path) {
            TempFiles.register(outputURL)
        }
        return outputURL
    }

    static func tempDirectory() -> URL {
        let tmp = Paths.tempDirectory
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    // MARK: - Helpers

    /// Copies directories and loose files under `<scratch>/bundle-<uuid>/<name>/` so the zip
    /// unpacks to a folder called `name`.
    private static func stageBundle(directories: [URL], files: [URL], name: String) throws -> URL {
        let fm = FileManager.default
        let root = tempDirectory().appendingPathComponent("bundle-\(UUID().uuidString)", isDirectory: true)
        let staging = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        TempFiles.register(root)

        var seen = Set<String>()
        func uniqueName(_ original: String) -> String {
            var candidate = original
            var counter = 2
            while seen.contains(candidate) {
                let stem = (original as NSString).deletingPathExtension
                let ext = (original as NSString).pathExtension
                candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
                counter += 1
            }
            seen.insert(candidate)
            return candidate
        }

        for dir in directories {
            let dest = staging.appendingPathComponent(uniqueName(dir.lastPathComponent))
            try fm.copyItem(at: dir, to: dest)
        }
        for file in files {
            let dest = staging.appendingPathComponent(uniqueName(file.lastPathComponent))
            try fm.copyItem(at: file, to: dest)
        }
        return staging
    }

    /// Resolves `--output` to a concrete file URL, refusing to clobber an existing file unless `overwrite` is set.
    static func resolveOutput(_ outputPath: String?, name: String, overwrite: Bool) throws -> URL {
        guard let outputPath = outputPath else {
            return plannedArchiveURL(name: name)
        }
        var url = InputResolver.expandPath(outputPath)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            url = url.appendingPathComponent("\(name).zip")
        } else if url.pathExtension.lowercased() != "zip" {
            url = url.appendingPathExtension("zip")
        }
        if FileManager.default.fileExists(atPath: url.path) && !overwrite {
            throw ShareError.refused("\(url.path) already exists", hint: "pass --force to overwrite it")
        }
        return url
    }

    static func fileSize(_ url: URL) -> Int64? {
        return HumanReadable.sizeOfFile(atPath: url.path)
    }
}
