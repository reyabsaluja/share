import AppKit
import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that everything share needs is in place."
    )

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    @Flag(name: .long, help: "Also test Mail and Messages automation (macOS may show permission prompts).")
    var automation = false

    struct Check {
        let name: String
        let ok: Bool
        let detail: String
        var warning = false
    }

    func run() throws {
        var checks: [Check] = []
        let fm = FileManager.default

        let os = ProcessInfo.processInfo.operatingSystemVersion
        checks.append(Check(name: "macOS", ok: os.majorVersion >= 12, detail: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)" + (os.majorVersion < 12 ? " (12 or newer required)" : "")))
        checks.append(Check(name: "share", ok: true, detail: "\(Version.current) at \(Paths.executableURL.path)"))

        let airdrop = AirDropBackend.isAvailable
        checks.append(Check(name: "AirDrop", ok: airdrop, detail: airdrop ? "available" : "unavailable (turn on Wi-Fi and Bluetooth)"))

        for (app, path) in [("Mail", "/System/Applications/Mail.app"), ("Messages", "/System/Applications/Messages.app"), ("Shortcuts", "/System/Applications/Shortcuts.app")] {
            let installed = fm.fileExists(atPath: path) || fm.fileExists(atPath: "/Applications/\(app).app")
            checks.append(Check(name: app, ok: installed, detail: installed ? "installed" : "not found"))
        }

        checks.append(Check(name: "shortcuts CLI", ok: fm.isExecutableFile(atPath: "/usr/bin/shortcuts"), detail: fm.isExecutableFile(atPath: "/usr/bin/shortcuts") ? "/usr/bin/shortcuts" : "missing"))
        checks.append(Check(name: "ditto", ok: fm.isExecutableFile(atPath: "/usr/bin/ditto"), detail: fm.isExecutableFile(atPath: "/usr/bin/ditto") ? "/usr/bin/ditto" : "missing (needed for zip)"))
        checks.append(Check(name: "git", ok: true, detail: GitContext.isAvailable ? "available" : "not found (branch names and .gitignore support disabled)", warning: !GitContext.isAvailable))

        let tmp = Packager.tempDirectory()
        let tmpWritable = fm.isWritableFile(atPath: tmp.path)
        let tmpStats = DirectoryStats.measure(tmp, fileLimit: 10_000)
        checks.append(Check(name: "scratch dir", ok: tmpWritable, detail: tmpWritable ? "\(tmp.path) (\(tmpStats.summary) in use)" : "\(tmp.path) not writable"))

        let configDirOK = (try? Paths.ensureConfigDirectory()) != nil && fm.isWritableFile(atPath: Paths.configDirectory.path)
        checks.append(Check(name: "config dir", ok: configDirOK, detail: configDirOK ? Paths.configDirectory.path : "\(Paths.configDirectory.path) not writable"))

        for (label, url) in [("config", Paths.configFile), ("local config", Paths.localConfigFile)] where fm.fileExists(atPath: url.path) {
            let valid = (try? JSONDecoder().decode(ShareConfig.self, from: Data(contentsOf: url))) != nil
            checks.append(Check(name: label, ok: valid, detail: valid ? url.path : "\(url.path) is not valid JSON"))
        }

        let aliasCount = Aliases.list().count
        checks.append(Check(name: "aliases", ok: true, detail: aliasCount == 0 ? "none (share alias <name> <address>)" : HumanReadable.count(aliasCount, "alias", "aliases")))

        let shell = CompletionsCommand.detectShell()
        let completionPaths: [String: String] = [
            "zsh": Paths.home.appendingPathComponent(".zsh/completions/_share").path,
            "bash": Paths.home.appendingPathComponent(".local/share/bash-completion/completions/share").path,
            "fish": Paths.home.appendingPathComponent(".config/fish/completions/share.fish").path,
        ]
        if let path = completionPaths[shell] {
            let installed = fm.fileExists(atPath: path)
            checks.append(Check(name: "completions", ok: true, detail: installed ? "\(shell) installed" : "\(shell) not installed (share completions --install)", warning: !installed))
        }

        if automation {
            for app in ["Mail", "Messages"] {
                let result = Subprocess.run("/usr/bin/osascript", arguments: ["-e", "tell application \"\(app)\" to get name"])
                if result.status == 0 {
                    checks.append(Check(name: "\(app) automation", ok: true, detail: "allowed"))
                } else if AppleScriptRunner.isAutomationDenied(result.stderr) {
                    checks.append(Check(name: "\(app) automation", ok: false, detail: "denied — System Settings → Privacy & Security → Automation"))
                } else {
                    checks.append(Check(name: "\(app) automation", ok: false, detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }

        let failed = checks.filter { !$0.ok }
        let warnings = checks.filter { $0.ok && $0.warning }

        if json {
            print(JSONOutput.format([
                "ok": failed.isEmpty,
                "checks": checks.map { ["name": $0.name, "ok": $0.ok, "warning": $0.warning, "detail": $0.detail] as [String: Any] },
            ] as [String: Any]))
        } else {
            print("\n" + Color.bold("share doctor") + "\n")
            for check in checks {
                let icon = check.ok ? (check.warning ? Color.yellow("!") : Color.green("✓")) : Color.red("✗")
                let detail = check.ok ? (check.warning ? Color.yellow(check.detail) : check.detail) : Color.red(check.detail)
                print("  \(icon) \(check.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(detail)")
            }
            print("")
            if failed.isEmpty && warnings.isEmpty {
                print(Color.green("  All checks passed."))
            } else if failed.isEmpty {
                print(Color.yellow("  All checks passed, \(HumanReadable.count(warnings.count, "suggestion")) above."))
            } else {
                print(Color.red("  \(HumanReadable.count(failed.count, "check")) failed."))
            }
            if !automation {
                print(Color.dim("  Run 'share doctor --automation' to test Mail/Messages permissions."))
            }
            print("")
        }

        if !failed.isEmpty {
            throw ExitCode.failure
        }
    }
}
