import ArgumentParser
import Foundation

struct AliasCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        abstract: "Manage recipient aliases (@name → email, phone, or a comma-separated group).",
        discussion: """
        share alias                       list aliases
        share alias rey rey@example.com   create or update
        share alias team a@x.com,b@y.com  group alias: 'share @team .' fans out to everyone
        share alias rey --remove          delete
        """
    )

    @Argument(help: "Alias name (with or without @).")
    var name: String?

    @Argument(help: "Email, phone, or comma-separated group. Omit to show the current value.")
    var value: String?

    @Flag(name: [.short, .long], help: "Remove the alias.")
    var remove = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        guard let name = name else {
            let all = Aliases.list()
            if json { print(JSONOutput.format(all)); return }
            if all.isEmpty {
                print("No aliases yet.")
                Log.hint("add one with: share alias rey rey@example.com")
                return
            }
            let width = all.keys.map(\.count).max() ?? 0
            for (key, val) in all.sorted(by: { $0.key < $1.key }) {
                let kind = val.contains(",") ? Color.dim(" (group)") : ""
                print("  @\(key.padding(toLength: width, withPad: " ", startingAt: 0))  →  \(val)\(kind)")
            }
            return
        }

        let key = name.hasPrefix("@") ? String(name.dropFirst()) : name

        if remove {
            guard try Aliases.remove(key) else {
                throw ShareError.usage("@\(key) is not set")
            }
            if json { print(JSONOutput.format(["ok": true, "removed": key])) } else { print("Removed @\(key)") }
            return
        }

        guard let value = value else {
            guard let existing = Aliases.resolve("@\(key)") else {
                throw ShareError.usage("@\(key) is not set", hint: "set it with: share alias \(key) <email-or-phone>")
            }
            if json { print(JSONOutput.format(["name": key, "value": existing])) } else { print("@\(key) → \(existing)") }
            return
        }

        for part in SmartRouter.recipients(from: value) where SmartRouter.detect(part) == nil {
            throw ShareError.usage("'\(part)' is not an email address, phone number, or existing @alias")
        }
        try Aliases.set(key, value: value)
        if json { print(JSONOutput.format(["ok": true, "name": key, "value": value])) } else { print("@\(key) → \(value)") }
    }
}
