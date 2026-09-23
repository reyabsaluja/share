import Foundation

struct SecretFinding: Equatable {
    let path: String
    let reason: String
}

/// Finds files that probably should not leave the machine: credentials, keys, tokens.
///
/// Two passes: file names (`.env`, `id_rsa`, `*.pem`, …) and a bounded content scan
/// for high-precision token formats (AWS, GitHub, Slack, Stripe, private-key headers, …).
enum SecretsDetector {
    /// File-name globs. Matched case-insensitively against the basename.
    static let sensitiveNamePatterns: [String] = [
        ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*.jks", "*.keystore", "*.ppk",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "*.ovpn",
        "credentials.json", "service-account*.json", "client_secret*.json",
        ".npmrc", ".pypirc", ".netrc", ".htpasswd", "secrets.yml", "secrets.yaml", "secrets.json",
        "*.kdbx", "*.asc", "*.gpg", "known_hosts",
    ]

    /// Names that look sensitive but are conventionally safe placeholders.
    static let safeSuffixes: [String] = [".example", ".sample", ".template", ".dist", ".pub"]

    static let contentPatterns: [(regex: NSRegularExpression, reason: String)] = {
        let sources: [(String, String)] = [
            (#"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----"#, "private key"),
            (#"\bAKIA[0-9A-Z]{16}\b"#, "AWS access key"),
            (#"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#, "GitHub token"),
            (#"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#, "GitHub token"),
            (#"\bglpat-[A-Za-z0-9_\-]{20,}\b"#, "GitLab token"),
            (#"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b"#, "Slack token"),
            (#"\bsk_live_[0-9a-zA-Z]{20,}\b"#, "Stripe live key"),
            (#"\bAIza[0-9A-Za-z_\-]{35}\b"#, "Google API key"),
            (#"\bsk-ant-[A-Za-z0-9_\-]{20,}\b"#, "Anthropic API key"),
            (#"\bsk-proj-[A-Za-z0-9_\-]{20,}\b"#, "OpenAI API key"),
            (#"\bnpm_[A-Za-z0-9]{36}\b"#, "npm token"),
            (#"\bSG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}\b"#, "SendGrid key"),
            (#"\bhf_[A-Za-z0-9]{30,}\b"#, "Hugging Face token"),
        ]
        return sources.compactMap { source, reason in
            guard let regex = try? NSRegularExpression(pattern: source) else { return nil }
            return (regex, reason)
        }
    }()

    static let maxContentFileBytes = 512 * 1024
    static let maxFilesScanned = 5000

    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "__pycache__", "Pods", ".gradle",
        "target", "dist", "build", "venv", ".venv", ".next", ".cache", ".swiftpm", "vendor",
    ]

    static func isSensitive(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        if safeSuffixes.contains(where: { lower.hasSuffix($0) }) { return false }
        return sensitiveNamePatterns.contains { Glob.fnmatch($0, lower) }
    }

    /// Scans a directory tree. `rules` (when given) filters out paths that will not be shared anyway.
    static func scan(directory: URL, rules: ExcludeRules? = nil, includeContents: Bool = true) -> [SecretFinding] {
        guard ShareConfig.current.skipSecretsScan != true else { return [] }
        var findings: [SecretFinding] = []
        let fm = FileManager.default
        let base = directory.standardized
        let relativizer = RelativePath(base: base)

        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }

        var scanned = 0
        while let url = enumerator.nextObject() as? URL {
            let relative = relativizer.of(url)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory == true

            if isDirectory {
                if skippedDirectories.contains(url.lastPathComponent) || rules?.isExcluded(relativePath: relative, isDirectory: true) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if rules?.isExcluded(relativePath: relative, isDirectory: false) == true { continue }
            if values?.isSymbolicLink == true { continue }

            if isSensitive(url.lastPathComponent) {
                findings.append(SecretFinding(path: relative, reason: "sensitive file name"))
                continue
            }

            guard includeContents, values?.isRegularFile == true, scanned < maxFilesScanned else { continue }
            let size = values?.fileSize ?? Int.max
            guard size <= maxContentFileBytes else { continue }
            scanned += 1
            if let reason = scanContents(of: url) {
                findings.append(SecretFinding(path: relative, reason: reason))
            }
        }

        return findings.sorted { $0.path < $1.path }
    }

    /// Checks a single file for token-like content. Returns the reason, or nil when clean.
    static func scanContents(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if data.prefix(1024).contains(0) { return nil }  // binary
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return scanContents(text)
    }

    static func scanContents(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for (regex, reason) in contentPatterns where regex.firstMatch(in: text, range: range) != nil {
            return reason
        }
        return nil
    }

    /// Scans and, when something is found, asks the user whether to continue.
    /// Returns false when the share should be aborted.
    static func warnIfNeeded(directory: URL, rules: ExcludeRules? = nil, quiet: Bool) -> Bool {
        let findings = scan(directory: directory, rules: rules)
        guard !findings.isEmpty else { return true }

        if !quiet || !Prompt.assumeYes {
            Log.warn("\(directory.lastPathComponent) contains files that look sensitive:")
            for finding in findings.prefix(10) {
                FileHandle.standardError.write(Data("  \(finding.path)  \(Color.dim("(\(finding.reason))"))\n".utf8))
            }
            if findings.count > 10 {
                FileHandle.standardError.write(Data("  … and \(findings.count - 10) more\n".utf8))
            }
        }

        if Prompt.assumeYes {
            if !quiet { Log.warn("continuing because --yes was given") }
            return true
        }

        guard let answer = Prompt.confirm("Share anyway?") else {
            Log.error("refusing to share sensitive files in non-interactive mode")
            Log.hint("pass --yes to override, use --smart to drop them, or add them to .shareignore")
            return false
        }
        return answer
    }

    static func relativePath(of url: URL, under base: URL) -> String {
        return RelativePath(base: base).of(url)
    }
}
