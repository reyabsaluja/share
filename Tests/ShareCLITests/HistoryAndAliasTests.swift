import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct HistoryTests {
        @Test func recordsAndTrims() throws {
            let sandbox = try Sandbox()
            var config = ShareConfig.empty
            config.historyLimit = 3
            try ShareConfig.write(config, to: Paths.configFile)

            for i in 0..<5 {
                History.record(destination: "zip", recipient: nil, items: ["item\(i)"], archivePath: nil)
            }
            let entries = History.load()
            #expect(entries.count == 3)
            #expect(entries.last?.items == ["item4"])
            #expect(entries.last?.cwd == FileManager.default.currentDirectoryPath)
            #expect(entries.last?.argv != nil)

            History.clear()
            #expect(History.load().isEmpty)
            _ = sandbox
        }

        @Test func recordingCanBeDisabled() throws {
            let sandbox = try Sandbox()
            History.recordingEnabled = false
            defer { History.recordingEnabled = true }
            History.record(destination: "zip", recipient: nil, items: ["x"], archivePath: nil)
            #expect(History.load().isEmpty)
            _ = sandbox
        }

        @Test func legacyEntriesReplayFromFields() throws {
            let json = #"[{"timestamp":"2026-01-01T00:00:00Z","destination":"email","recipient":"a@b.co","items":["."],"archivePath":null}]"#
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([HistoryEntry].self, from: Data(json.utf8))
            #expect(entries[0].replayArguments == ["email", "a@b.co", "."])
            let modern = HistoryEntry(destination: "zip", recipient: nil, items: ["."], archivePath: nil, argv: ["zip", ".", "--smart"], cwd: "/tmp")
            #expect(modern.replayArguments == ["zip", ".", "--smart"])
        }
    }

    @Suite struct AliasTests {
        @Test func setResolveExpandRemove() throws {
            let sandbox = try Sandbox()
            try Aliases.set("@rey", value: "rey@example.com")
            #expect(Aliases.resolve("@rey") == "rey@example.com")
            #expect(Aliases.resolve("rey") == nil)
            #expect(Aliases.resolve("rey", allowBare: true) == "rey@example.com")
            #expect(Aliases.names() == ["rey"])

            try Aliases.set("team", value: "a@x.com, b@y.com")
            #expect(Aliases.expand("@team") == ["a@x.com", "b@y.com"])

            #expect(try Aliases.remove("rey"))
            #expect(!(try Aliases.remove("rey")))
            #expect(Aliases.resolve("@rey") == nil)
            _ = sandbox
        }

        @Test func validatesNames() throws {
            let sandbox = try Sandbox()
            #expect(throws: ShareError.self) { try Aliases.set("bad name", value: "a@b.co") }
            #expect(throws: ShareError.self) { try Aliases.set("", value: "a@b.co") }
            try Aliases.set("ok-name.1", value: "a@b.co")
            _ = sandbox
        }
    }
}
