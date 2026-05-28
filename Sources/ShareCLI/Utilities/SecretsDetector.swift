import Foundation

enum SecretsDetector {
    static let sensitivePatterns: [String] = [
        ".env",
        ".env.local",
        ".env.production",
        ".env.development",
        "id_rsa",
        "id_ed25519",
        "id_ecdsa",
        ".pem",
        ".key",
        ".p12",
        ".pfx",
        "credentials.json",
        "service-account.json",
        ".npmrc",
        ".pypirc",
    ]

    static func scan(directory: URL) -> [String] {
        var found: Set<String> = []
        let fm = FileManager.default
        let basePath = directory.standardized.path

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        let skipDirs: Set<String> = [".git", "node_modules", ".build", "DerivedData", "__pycache__", "Pods", ".gradle"]

        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if skipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if isSensitive(name) {
                let fullPath = url.standardized.path
                let relative = String(fullPath.dropFirst(basePath.count + 1))
                found.insert(relative)
            }
        }

        return Array(found).sorted()
    }

    static func isSensitive(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        for pattern in sensitivePatterns {
            if lower == pattern || lower.hasSuffix(pattern) {
                return true
            }
        }
        return false
    }

    static func warnIfNeeded(directory: URL, quiet: Bool) -> Bool {
        let secrets = scan(directory: directory)
        guard !secrets.isEmpty else { return true }

        if quiet { return true }

        Log.error("this folder contains files that may be sensitive:")
        for secret in secrets.prefix(10) {
            fputs("  \(secret)\n", stderr)
        }
        if secrets.count > 10 {
            fputs("  … and \(secrets.count - 10) more\n", stderr)
        }

        guard isatty(fileno(stdin)) != 0 else {
            Log.error("refusing to share in non-interactive mode. Use --yes to override.")
            return false
        }

        fputs("Continue? [y/N] ", stderr)
        guard let answer = readLine(), answer.lowercased().hasPrefix("y") else {
            return false
        }
        return true
    }
}
