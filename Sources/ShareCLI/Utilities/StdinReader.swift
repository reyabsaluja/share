import Foundation

/// Reads piped input without ever blocking on an idle terminal or an open-but-silent pipe.
enum StdinReader {
    private static var cached: String??

    /// Returns piped stdin content, or `nil` when stdin is a terminal or has no data.
    ///
    /// A short poll avoids hanging when the CLI is launched by a tool that keeps
    /// stdin open but never writes to it (editors, agents, CI runners).
    static func readIfPiped(timeoutMilliseconds: Int32 = 150) -> String? {
        if let cached = cached { return cached }
        guard isatty(STDIN_FILENO) == 0 else {
            cached = .some(nil)
            return nil
        }

        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, timeoutMilliseconds)
        let flags = Int32(descriptor.revents)
        guard ready > 0, flags & (POLLIN | POLLHUP) != 0 else {
            cached = .some(nil)
            return nil
        }

        let result = readAll()
        cached = .some(result)
        return result
    }

    /// Reads stdin to EOF unconditionally. Use when the user explicitly asked for stdin (`-`).
    static func readAll() -> String? {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
