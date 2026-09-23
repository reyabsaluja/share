import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct ConfigTests {
        @Test func legacyKeysStillDecode() throws {
            let json = #"{"defaultSmart": true, "defaultFrom": "me@x.com", "autoNotify": true, "autoCopyZip": false, "defaultSubjectTemplate": "{repo}"}"#
            let config = try JSONDecoder().decode(ShareConfig.self, from: Data(json.utf8))
            #expect(config.smart == true)
            #expect(config.from == "me@x.com")
            #expect(config.notify == true)
            #expect(config.copyZip == false)
            #expect(config.subjectTemplate == "{repo}")
        }

        @Test func unknownKeysAreIgnored() throws {
            let config = try JSONDecoder().decode(ShareConfig.self, from: Data(#"{"future": 1, "smart": false}"#.utf8))
            #expect(config.smart == false)
        }

        @Test func mergePrefersOverrides() {
            var global = ShareConfig.empty
            global.smart = true
            global.from = "global@x.com"
            var local = ShareConfig.empty
            local.from = "local@x.com"
            let merged = global.merged(with: local)
            #expect(merged.smart == true)
            #expect(merged.from == "local@x.com")
        }

        @Test func setValidatesTypes() throws {
            var config = ShareConfig.empty
            try config.set(key: "smart", rawValue: "yes")
            #expect(config.smart == true)
            try config.set(key: "historyLimit", rawValue: "25")
            #expect(config.historyLimit == 25)
            try config.set(key: "from", rawValue: "me@x.com")
            #expect(config.value(forKey: "from") == "me@x.com")
            try config.set(key: "smart", rawValue: nil)
            #expect(config.smart == nil)
            #expect(throws: ShareError.self) { try config.set(key: "smart", rawValue: "maybe") }
            #expect(throws: ShareError.self) { try config.set(key: "historyLimit", rawValue: "-1") }
            #expect(throws: ShareError.self) { try config.set(key: "servePort", rawValue: "70000") }
            #expect(throws: ShareError.self) { try config.set(key: "nope", rawValue: "1") }
        }

        @Test func loadMergesGlobalAndLocalAndSurvivesMalformedFiles() throws {
            let sandbox = try Sandbox()
            var global = ShareConfig.empty
            global.smart = true
            global.historyLimit = 5
            try ShareConfig.write(global, to: Paths.configFile)
            #expect(ShareConfig.load().smart == true)
            #expect(ShareConfig.current.historyLimit == 5)

            try "not json".write(to: Paths.configFile, atomically: true, encoding: .utf8)
            ShareConfig.invalidate()
            #expect(ShareConfig.load() == .empty)
            _ = sandbox
        }

        @Test func documentedKeysRoundTrip() throws {
            var config = ShareConfig.empty
            for (key, _) in ShareConfig.documentedKeys {
                let sample: String
                switch key {
                case "from": sample = "a@b.co"
                case "subjectTemplate": sample = "{repo}"
                case "historyLimit", "airdropTimeout": sample = "7"
                case "servePort": sample = "8080"
                default: sample = "true"
                }
                try config.set(key: key, rawValue: sample)
                #expect(config.value(forKey: key) == sample, "\(key) should round-trip")
            }
        }
    }
}
