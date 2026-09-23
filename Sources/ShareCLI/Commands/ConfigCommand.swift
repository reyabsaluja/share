import ArgumentParser
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View or change settings.",
        discussion: """
        share config                     show the effective settings
        share config set smart true      set a key in ~/.config/share/config.json
        share config set from me@x.com --local   write to ./.share.json instead
        share config unset smart
        share config get from
        share config path
        share config edit                open the config file in $EDITOR
        share config keys                list every key with a description
        """,
        subcommands: [Get.self, Set.self, Unset.self, PathCommand.self, Edit.self, Keys.self]
    )

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        let config = ShareConfig.load()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(config), encoding: .utf8) ?? "{}")
            return
        }
        let global = FileManager.default.fileExists(atPath: Paths.configFile.path)
        let local = FileManager.default.fileExists(atPath: Paths.localConfigFile.path)
        print(Color.dim("global: \(Paths.configFile.path)\(global ? "" : " (not created yet)")"))
        if local { print(Color.dim("local:  \(Paths.localConfigFile.path)")) }
        print("")
        var any = false
        for (key, _) in ShareConfig.documentedKeys {
            if let value = config.value(forKey: key) {
                print("  \(key.padding(toLength: 16, withPad: " ", startingAt: 0)) \(value)")
                any = true
            }
        }
        if !any {
            print("  (all defaults)")
            Log.hint("see the keys with 'share config keys'")
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print one setting.")
        @Argument(help: "Config key.") var key: String
        func run() throws {
            guard ShareConfig.documentedKeys.contains(where: { $0.key == key }) else {
                throw ShareError.configError("unknown config key '\(key)'", hint: "see 'share config keys'")
            }
            if let value = ShareConfig.load().value(forKey: key) {
                print(value)
            } else {
                print(Color.dim("(unset)"))
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set one setting.")
        @Argument(help: "Config key.") var key: String
        @Argument(help: "New value.") var value: String
        @Flag(name: .long, help: "Write to ./.share.json instead of the global file.") var local = false
        func run() throws {
            let url = local ? Paths.localConfigFile : Paths.configFile
            var config = ShareConfig.read(from: url) ?? .empty
            try config.set(key: key, rawValue: value)
            try ShareConfig.write(config, to: url)
            print("\(key) = \(config.value(forKey: key) ?? value)  " + Color.dim("(\(url.path))"))
        }
    }

    struct Unset: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove one setting.")
        @Argument(help: "Config key.") var key: String
        @Flag(name: .long, help: "Edit ./.share.json instead of the global file.") var local = false
        func run() throws {
            let url = local ? Paths.localConfigFile : Paths.configFile
            var config = ShareConfig.read(from: url) ?? .empty
            try config.set(key: key, rawValue: nil)
            try ShareConfig.write(config, to: url)
            print("unset \(key)  " + Color.dim("(\(url.path))"))
        }
    }

    struct PathCommand: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "path", abstract: "Print the config file locations.")
        func run() throws {
            print(Paths.configFile.path)
            if FileManager.default.fileExists(atPath: Paths.localConfigFile.path) {
                print(Paths.localConfigFile.path)
            }
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open the config file in $EDITOR.")
        @Flag(name: .long, help: "Edit ./.share.json instead of the global file.") var local = false
        func run() throws {
            let url = local ? Paths.localConfigFile : Paths.configFile
            if !FileManager.default.fileExists(atPath: url.path) {
                try ShareConfig.write(.empty, to: url)
            }
            let editor = ProcessInfo.processInfo.environment["VISUAL"] ?? ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\(editor) \"$0\"", url.path]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            ShareConfig.invalidate()
            if ShareConfig.read(from: url) == nil && FileManager.default.fileExists(atPath: url.path) {
                throw ShareError.configError("\(url.path) is not valid JSON after editing")
            }
        }
    }

    struct Keys: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List every config key.")
        func run() throws {
            for (key, description) in ShareConfig.documentedKeys {
                print("  \(key.padding(toLength: 16, withPad: " ", startingAt: 0)) \(Color.dim(description))")
            }
        }
    }
}
