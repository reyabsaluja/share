import Foundation

enum Destination {
    case airdrop
    case email(String)
    case messages(String)
}

enum SmartRouter {
    static func detect(_ firstArg: String) -> Destination? {
        if let resolved = Aliases.resolve(firstArg) {
            return detect(resolved)
        }
        if looksLikeEmail(firstArg) {
            return .email(firstArg)
        }
        if looksLikePhone(firstArg) {
            return .messages(firstArg)
        }
        return nil
    }

    static func looksLikeEmail(_ str: String) -> Bool {
        let parts = str.split(separator: "@")
        guard parts.count == 2 else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func looksLikePhone(_ str: String) -> Bool {
        let cleaned = str.filter { $0.isNumber || $0 == "+" }
        if cleaned.hasPrefix("+") && cleaned.count >= 10 && cleaned.count <= 15 {
            return true
        }
        let digitsOnly = str.filter { $0.isNumber }
        return digitsOnly.count >= 10 && digitsOnly.count <= 11 && !str.contains(".")
    }
}
