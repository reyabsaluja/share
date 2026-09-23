import AppKit
import ArgumentParser
import Foundation

/// Custom entry point so errors get consistent formatting, hints, JSON output and exit codes.
@main
enum ShareMain {
    static func main() {
        // Keep stdout line-buffered even when piped so it interleaves sanely with stderr.
        setvbuf(stdout, nil, _IOLBF, 0)
        let arguments = Array(CommandLine.arguments.dropFirst())
        configureGlobals(from: arguments)
        TempFiles.pruneOld()

        do {
            var command = try ShareCommand.parseAsRoot(arguments)
            try command.run()
        } catch let error as ShareError {
            report(error)
            exit(error.exitCode)
        } catch let error as ExitCode {
            exit(error.rawValue)
        } catch {
            if JSONOutput.enabled, !isHelpOrCleanExit(error) {
                print(JSONOutput.error(code: "error", message: ShareCommand.message(for: error), exitCode: ShareCommand.exitCode(for: error).rawValue))
                exit(ShareCommand.exitCode(for: error).rawValue)
            }
            ShareCommand.exit(withError: error)
        }
    }

    private static func configureGlobals(from arguments: [String]) {
        JSONOutput.enabled = arguments.contains("--json")
        if arguments.contains("--no-color") {
            Color.mode = .never
        } else if arguments.contains("--color") {
            Color.mode = .always
        } else if let configured = ShareConfig.current.color {
            Color.mode = configured ? .always : .never
        }
        if arguments.contains("--yes") || arguments.contains("-y") {
            Prompt.assumeYes = true
        }
    }

    private static func report(_ error: ShareError) {
        if JSONOutput.enabled {
            print(JSONOutput.error(error))
            return
        }
        if case .userCancelled = error {
            Log.info(Color.dim("cancelled"))
            return
        }
        Log.error(error.description)
        if let hint = error.hint {
            Log.hint(hint)
        }
    }

    private static func isHelpOrCleanExit(_ error: Error) -> Bool {
        return ShareCommand.exitCode(for: error).rawValue == 0
    }
}
