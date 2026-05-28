import Foundation

enum StdinReader {
    static func readIfPiped() -> String? {
        guard isatty(fileno(stdin)) == 0 else { return nil }
        var lines: [String] = []
        while let line = readLine(strippingNewline: false) {
            lines.append(line)
        }
        let text = lines.joined()
        return text.isEmpty ? nil : text
    }
}
