import Foundation

enum SizeWarning {
    static let emailLimit: Int64 = 25 * 1024 * 1024
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024

    static func check(items: [PreparedShareItem], destination: String, quiet: Bool) -> Bool {
        let totalSize = items.compactMap(\.sizeBytes).reduce(0, +)

        if destination == "email" && totalSize > emailLimit {
            if !quiet {
                Log.error("total size \(HumanReadable.fileSize(totalSize)) exceeds typical email limit (25 MB)")
                Log.hint("consider using 'share airdrop' or 'share zip --output' instead")
            }
            guard isatty(fileno(stdin)) != 0 else { return false }
            fputs("Continue anyway? [y/N] ", stderr)
            guard let answer = readLine(), answer.lowercased().hasPrefix("y") else {
                return false
            }
        }

        if totalSize > largeFileThreshold && !quiet {
            Log.info("Sharing \(HumanReadable.fileSize(totalSize)) — this may take a moment")
        }

        return true
    }
}
