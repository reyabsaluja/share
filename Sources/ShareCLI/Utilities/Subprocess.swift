import Foundation

/// Minimal synchronous process runner that never deadlocks on full pipes.
struct Subprocess {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        stdin: String? = nil,
        environment: [String: String]? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let dir = currentDirectory { process.currentDirectoryURL = dir }
        if let env = environment { process.environment = env }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var inPipe: Pipe?
        if stdin != nil {
            inPipe = Pipe()
            process.standardInput = inPipe
        }

        do {
            try process.run()
        } catch {
            return Result(status: 127, stdout: "", stderr: error.localizedDescription)
        }

        if let input = stdin, let pipe = inPipe {
            pipe.fileHandleForWriting.write(Data(input.utf8))
            try? pipe.fileHandleForWriting.close()
        }

        // Drain both pipes concurrently so neither can fill up and block the child.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
