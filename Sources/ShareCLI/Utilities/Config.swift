import Foundation

/// User configuration, merged from two JSON files:
///
/// 1. `~/.config/share/config.json` (global)
/// 2. `./.share.json` in the current directory (project-local, overrides global)
///
/// Every key is optional. Unknown keys are ignored so the file can be shared
/// between versions. Legacy key names from 0.x (`defaultSmart`, `defaultFrom`,
/// `defaultSubjectTemplate`, `autoNotify`, `autoCopyZip`) are still accepted.
struct ShareConfig: Codable, Equatable {
    /// Apply `--smart` exclusions to every directory share by default.
    var smart: Bool?
    /// When smart mode runs inside a git repository, honor `.gitignore` via `git ls-files`.
    var gitignore: Bool?
    /// Default sender address for `share email`.
    var from: String?
    /// Template for generated email subjects. Variables: {repo} {branch} {name} {date} {user} {host}.
    var subjectTemplate: String?
    /// Post a macOS notification after every successful share.
    var notify: Bool?
    /// Copy the archive path to the clipboard after `share zip`.
    var copyZip: Bool?
    /// Force colors on/off. Omit for auto-detection.
    var color: Bool?
    /// Number of history entries to keep (default 100).
    var historyLimit: Int?
    /// Seconds to wait for the AirDrop panel before giving up (default 300).
    var airdropTimeout: Int?
    /// Default port for `share serve` (default: random free port).
    var servePort: Int?
    /// Skip the sensitive-file scan entirely. Not recommended.
    var skipSecretsScan: Bool?
    /// Use the SMS account instead of iMessage for `share messages`.
    var sms: Bool?

    static let empty = ShareConfig()

    /// Keys accepted by `share config set`, with a short description each.
    static let documentedKeys: [(key: String, description: String)] = [
        ("smart", "bool   apply --smart exclusions to every directory share"),
        ("gitignore", "bool   honor .gitignore during --smart (default true)"),
        ("from", "string default sender address for email"),
        ("subjectTemplate", "string email subject template, e.g. \"{repo} ({branch})\""),
        ("notify", "bool   macOS notification after every successful share"),
        ("copyZip", "bool   copy archive path to clipboard after 'share zip' (default true)"),
        ("color", "bool   force colored output on or off"),
        ("historyLimit", "int    history entries to keep (default 100)"),
        ("airdropTimeout", "int    seconds to wait for the AirDrop panel (default 300)"),
        ("servePort", "int    fixed port for 'share serve'"),
        ("skipSecretsScan", "bool   disable the sensitive-file scan (not recommended)"),
        ("sms", "bool   use the SMS account for messages instead of iMessage"),
    ]

    private enum CodingKeys: String, CodingKey {
        case smart, gitignore, from, subjectTemplate, notify, copyZip, color, historyLimit
        case airdropTimeout, servePort, skipSecretsScan, sms
        // Legacy names
        case defaultSmart, defaultFrom, defaultSubjectTemplate, autoNotify, autoCopyZip
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smart = try c.decodeIfPresent(Bool.self, forKey: .smart) ?? c.decodeIfPresent(Bool.self, forKey: .defaultSmart)
        gitignore = try c.decodeIfPresent(Bool.self, forKey: .gitignore)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? c.decodeIfPresent(String.self, forKey: .defaultFrom)
        subjectTemplate = try c.decodeIfPresent(String.self, forKey: .subjectTemplate)
            ?? c.decodeIfPresent(String.self, forKey: .defaultSubjectTemplate)
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? c.decodeIfPresent(Bool.self, forKey: .autoNotify)
        copyZip = try c.decodeIfPresent(Bool.self, forKey: .copyZip) ?? c.decodeIfPresent(Bool.self, forKey: .autoCopyZip)
        color = try c.decodeIfPresent(Bool.self, forKey: .color)
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit)
        airdropTimeout = try c.decodeIfPresent(Int.self, forKey: .airdropTimeout)
        servePort = try c.decodeIfPresent(Int.self, forKey: .servePort)
        skipSecretsScan = try c.decodeIfPresent(Bool.self, forKey: .skipSecretsScan)
        sms = try c.decodeIfPresent(Bool.self, forKey: .sms)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(smart, forKey: .smart)
        try c.encodeIfPresent(gitignore, forKey: .gitignore)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encodeIfPresent(subjectTemplate, forKey: .subjectTemplate)
        try c.encodeIfPresent(notify, forKey: .notify)
        try c.encodeIfPresent(copyZip, forKey: .copyZip)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(historyLimit, forKey: .historyLimit)
        try c.encodeIfPresent(airdropTimeout, forKey: .airdropTimeout)
        try c.encodeIfPresent(servePort, forKey: .servePort)
        try c.encodeIfPresent(skipSecretsScan, forKey: .skipSecretsScan)
        try c.encodeIfPresent(sms, forKey: .sms)
    }

    // MARK: - Merging

    /// Returns a copy where every non-nil value in `other` wins.
    func merged(with other: ShareConfig) -> ShareConfig {
        var result = self
        if let v = other.smart { result.smart = v }
        if let v = other.gitignore { result.gitignore = v }
        if let v = other.from { result.from = v }
        if let v = other.subjectTemplate { result.subjectTemplate = v }
        if let v = other.notify { result.notify = v }
        if let v = other.copyZip { result.copyZip = v }
        if let v = other.color { result.color = v }
        if let v = other.historyLimit { result.historyLimit = v }
        if let v = other.airdropTimeout { result.airdropTimeout = v }
        if let v = other.servePort { result.servePort = v }
        if let v = other.skipSecretsScan { result.skipSecretsScan = v }
        if let v = other.sms { result.sms = v }
        return result
    }

    // MARK: - Loading

    private static var cache: ShareConfig?

    /// The effective configuration (global merged with project-local). Cached per process.
    static var current: ShareConfig {
        if let cache = cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    /// Drop the cache. Used after `share config set` and in tests.
    static func invalidate() { cache = nil }

    static func load() -> ShareConfig {
        var config = ShareConfig.empty
        if let global = read(from: Paths.configFile) { config = config.merged(with: global) }
        if let local = read(from: Paths.localConfigFile) { config = config.merged(with: local) }
        return config
    }

    /// Reads one config file. Returns nil when it does not exist. Warns (once) when it is malformed.
    static func read(from url: URL) -> ShareConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ShareConfig.self, from: data)
        } catch {
            Log.warn("ignoring malformed config \(url.path): \(Self.describe(error))")
            return nil
        }
    }

    static func write(_ config: ShareConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
        invalidate()
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .keyNotFound(_, let ctx), .dataCorrupted(let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                return path.isEmpty ? ctx.debugDescription : "\(path): \(ctx.debugDescription)"
            @unknown default:
                return String(describing: error)
            }
        }
        return error.localizedDescription
    }

    // MARK: - Key/value access for `share config`

    func value(forKey key: String) -> String? {
        switch key {
        case "smart": return smart.map(String.init)
        case "gitignore": return gitignore.map(String.init)
        case "from": return from
        case "subjectTemplate": return subjectTemplate
        case "notify": return notify.map(String.init)
        case "copyZip": return copyZip.map(String.init)
        case "color": return color.map(String.init)
        case "historyLimit": return historyLimit.map(String.init)
        case "airdropTimeout": return airdropTimeout.map(String.init)
        case "servePort": return servePort.map(String.init)
        case "skipSecretsScan": return skipSecretsScan.map(String.init)
        case "sms": return sms.map(String.init)
        default: return nil
        }
    }

    /// Sets a key from its string form. Pass `nil` to unset. Throws on unknown keys or bad values.
    mutating func set(key: String, rawValue: String?) throws {
        func bool() throws -> Bool? {
            guard let raw = rawValue else { return nil }
            switch raw.lowercased() {
            case "true", "yes", "on", "1": return true
            case "false", "no", "off", "0": return false
            default: throw ShareError.configError("'\(key)' expects true or false, got '\(raw)'")
            }
        }
        func int() throws -> Int? {
            guard let raw = rawValue else { return nil }
            guard let value = Int(raw), value >= 0 else {
                throw ShareError.configError("'\(key)' expects a non-negative integer, got '\(raw)'")
            }
            return value
        }
        switch key {
        case "smart": smart = try bool()
        case "gitignore": gitignore = try bool()
        case "from": from = rawValue
        case "subjectTemplate": subjectTemplate = rawValue
        case "notify": notify = try bool()
        case "copyZip": copyZip = try bool()
        case "color": color = try bool()
        case "historyLimit": historyLimit = try int()
        case "airdropTimeout": airdropTimeout = try int()
        case "servePort":
            let port = try int()
            if let p = port, p > 65535 { throw ShareError.configError("'servePort' must be 0–65535") }
            servePort = port
        case "skipSecretsScan": skipSecretsScan = try bool()
        case "sms": sms = try bool()
        default:
            let known = Self.documentedKeys.map(\.key).joined(separator: ", ")
            throw ShareError.configError("unknown config key '\(key)'", hint: "known keys: \(known)")
        }
    }
}
