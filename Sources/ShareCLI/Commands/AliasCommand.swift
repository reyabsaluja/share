import ArgumentParser
import Foundation

struct AliasCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        abstract: "Manage recipient aliases (@name → address/phone)."
    )

    @Argument(help: "Alias name to set/remove, or empty to list all.")
    var name: String?

    @Argument(help: "Value to assign (email or phone). Omit to show current value.")
    var value: String?

    @Flag(name: [.short, .long], help: "Remove the alias.")
    var remove = false

    func run() throws {
        guard let name = name else {
            let all = Aliases.list()
            if all.isEmpty {
                print("No aliases configured.")
                print("Add one: share alias rey rey@example.com")
            } else {
                let maxLen = all.keys.map(\.count).max() ?? 0
                for (key, val) in all.sorted(by: { $0.key < $1.key }) {
                    let padded = key.padding(toLength: maxLen, withPad: " ", startingAt: 0)
                    print("  @\(padded) → \(val)")
                }
            }
            return
        }

        if remove {
            try Aliases.remove(name)
            print("Removed @\(name)")
            return
        }

        guard let value = value else {
            if let existing = Aliases.resolve("@\(name)") {
                print("@\(name) → \(existing)")
            } else {
                print("@\(name) is not set")
            }
            return
        }

        try Aliases.set(name, value: value)
        print("@\(name) → \(value)")
    }
}
