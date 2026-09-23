import Foundation

enum Destination: Equatable {
    case airdrop
    case email(String)
    case messages(String)

    var name: String {
        switch self {
        case .airdrop: return "airdrop"
        case .email: return "email"
        case .messages: return "messages"
        }
    }

    var recipient: String? {
        switch self {
        case .airdrop: return nil
        case .email(let r), .messages(let r): return r
        }
    }
}

/// Decides where a share goes from the shape of a recipient argument.
///
/// `@alias` (or a bare alias name when `allowBareAlias` is set) resolves first; then
/// anything with `user@host.tld` is email and anything with 10–15 digits is a phone number.
enum SmartRouter {
    static func detect(_ argument: String, allowBareAlias: Bool = false, depth: Int = 0) -> Destination? {
        if depth < 10, let resolved = Aliases.resolve(argument, allowBare: allowBareAlias), resolved != argument {
            return detect(resolved, depth: depth + 1)
        }
        if argument.lowercased() == "airdrop" {
            return .airdrop
        }
        if looksLikeEmail(argument) {
            return .email(argument)
        }
        if looksLikePhone(argument) {
            return .messages(normalizePhone(argument))
        }
        return nil
    }

    /// Resolves a possibly comma-separated recipient list, expanding aliases (including group aliases).
    static func recipients(from argument: String, allowBareAlias: Bool = false) -> [String] {
        var result: [String] = []
        for part in argument.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            if let expanded = Aliases.expand(part, allowBare: allowBareAlias) {
                result.append(contentsOf: expanded)
            } else {
                result.append(part)
            }
        }
        return result
    }

    static func looksLikeEmail(_ str: String) -> Bool {
        guard !str.contains(where: { $0.isWhitespace || $0 == "/" }) else { return false }
        let parts = str.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return !domain.contains("..")
    }

    static func looksLikePhone(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed = Set("0123456789+-() .")
        guard trimmed.allSatisfy({ allowed.contains($0) }) else { return false }
        // IP addresses and version-like strings contain dots between digit groups; phone numbers do not.
        if trimmed.contains(".") { return false }
        let digits = trimmed.filter(\.isNumber)
        if trimmed.hasPrefix("+") {
            return digits.count >= 7 && digits.count <= 15
        }
        // Without a country code only North-American-length numbers are accepted; anything
        // longer (dates, IDs, international numbers without +) is too ambiguous.
        return digits.count >= 10 && digits.count <= 11
    }

    /// Strips formatting so Messages gets a clean handle: "+1 (437) 555-0100" → "+14375550100".
    static func normalizePhone(_ str: String) -> String {
        let digits = str.filter(\.isNumber)
        return str.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" + digits : digits
    }
}
