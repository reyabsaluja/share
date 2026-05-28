import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check macOS integration status."
    )

    @Flag(name: .long, help: "Output result as JSON.")
    var json = false

    func run() throws {
        var checks: [(String, Bool, String)] = []

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionStr = "\(version.majorVersion).\(version.minorVersion)"
        checks.append(("macOS", true, versionStr))

        let execPath = CommandLine.arguments[0]
        checks.append(("Binary", true, execPath))

        let airdropAvailable = checkAirDrop()
        checks.append(("AirDrop", airdropAvailable, airdropAvailable ? "available" : "unavailable"))

        let mailInstalled = FileManager.default.fileExists(atPath: "/System/Applications/Mail.app") ||
            FileManager.default.fileExists(atPath: "/Applications/Mail.app")
        checks.append(("Mail", mailInstalled, mailInstalled ? "installed" : "not found"))

        let messagesInstalled = FileManager.default.fileExists(atPath: "/System/Applications/Messages.app") ||
            FileManager.default.fileExists(atPath: "/Applications/Messages.app")
        checks.append(("Messages", messagesInstalled, messagesInstalled ? "installed" : "not found"))

        let shortcutsAvailable = FileManager.default.fileExists(atPath: "/usr/bin/shortcuts")
        checks.append(("Shortcuts", shortcutsAvailable, shortcutsAvailable ? "available" : "not found"))

        let dittoAvailable = FileManager.default.fileExists(atPath: "/usr/bin/ditto")
        checks.append(("Packager", dittoAvailable, dittoAvailable ? "ditto available" : "ditto not found"))

        let tmpDir = Packager.tempDirectory()
        let tmpWritable = FileManager.default.isWritableFile(atPath: tmpDir.path)
        checks.append(("Temp dir", tmpWritable, tmpWritable ? "writable" : "not writable"))

        if json {
            var result: [String: Any] = ["ok": true]
            var checksDict: [[String: Any]] = []
            for (name, ok, detail) in checks {
                checksDict.append(["name": name, "ok": ok, "detail": detail])
                if !ok { result["ok"] = false }
            }
            result["checks"] = checksDict
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("\nshare doctor\n")
            let allPassed = checks.allSatisfy { $0.1 }
            for (name, ok, detail) in checks {
                let icon = ok ? "✅" : "❌"
                let paddedName = name.padding(toLength: 12, withPad: " ", startingAt: 0)
                print("\(paddedName)  \(detail) \(icon)")
            }
            print("")
            if allPassed {
                print("All checks passed.")
            } else {
                print("Some checks failed. See above for details.")
            }
        }
    }

    private func checkAirDrop() -> Bool {
        // NSSharingService availability check requires AppKit to be loaded
        // We do a basic check here
        #if canImport(AppKit)
        return true
        #else
        return false
        #endif
    }
}
