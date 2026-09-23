import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct SecretsDetectorTests {
        @Test func sensitiveNames() {
            for name in [".env", ".env.production", "id_rsa", "server.pem", "cert.key", "keystore.jks", ".npmrc", "credentials.json", "service-account-prod.json", ".netrc"] {
                #expect(SecretsDetector.isSensitive(name), "\(name) should be flagged")
            }
            for name in [".env.example", ".env.sample", "id_rsa.pub", "README.md", "environment.ts", "key.swift", "keys.md"] {
                #expect(!SecretsDetector.isSensitive(name), "\(name) should not be flagged")
            }
        }

        /// Test tokens are assembled at runtime so no literal secret-shaped string lives in the repo
        /// (GitHub push protection would otherwise reject the file).
        static func fake(_ prefix: String, _ length: Int, alphabet: String = "abcdefghijklmnopqrstuvwxyz0123456789") -> String {
            let chars = Array(alphabet)
            return prefix + String((0..<length).map { chars[$0 % chars.count] })
        }

        @Test func contentPatterns() {
            #expect(SecretsDetector.scanContents("-----BEGIN RSA PRIVATE KEY-----\nabc") == "private key")
            #expect(SecretsDetector.scanContents("key = " + Self.fake("AKIA", 16, alphabet: "ABCDEFGHIJKLMNOP")) == "AWS access key")
            #expect(SecretsDetector.scanContents(Self.fake("ghp_", 40)) == "GitHub token")
            #expect(SecretsDetector.scanContents(Self.fake("xoxb-", 24)) == "Slack token")
            #expect(SecretsDetector.scanContents(Self.fake("sk_" + "live_", 26)) == "Stripe live key")
            #expect(SecretsDetector.scanContents(Self.fake("sk-ant-", 30)) == "Anthropic API key")
            #expect(SecretsDetector.scanContents("let x = 42 // nothing to see") == nil)
            #expect(SecretsDetector.scanContents("AKIA-not-a-key") == nil)
        }

        @Test func scanFindsNamesAndContentsButSkipsExcludedAndBinary() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/.env", "X=1")
            try sandbox.file("proj/src/config.js", "const t = '" + Self.fake("ghp_", 40) + "'")
            try sandbox.file("proj/node_modules/x/.env", "X=1")
            try sandbox.file("proj/README.md", "clean")
            try Data([0, 1, 2, 65, 75, 73, 65]).write(to: dir.appendingPathComponent("blob.bin"))

            let all = SecretsDetector.scan(directory: dir)
            #expect(all.map(\.path) == [".env", "src/config.js"])
            #expect(all[1].reason == "GitHub token")

            let rules = ExcludeRules(lines: [".env"])
            let filtered = SecretsDetector.scan(directory: dir, rules: rules)
            #expect(filtered.map(\.path) == ["src/config.js"])

            let namesOnly = SecretsDetector.scan(directory: dir, includeContents: false)
            #expect(namesOnly.map(\.path) == [".env"])
        }

        @Test func scanCanBeDisabledByConfig() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/.env", "X=1")
            var config = ShareConfig.empty
            config.skipSecretsScan = true
            try ShareConfig.write(config, to: Paths.configFile)
            #expect(SecretsDetector.scan(directory: dir).isEmpty)
        }

        @Test func warnIfNeededHonorsPromptAndYes() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/.env", "X=1")

            Prompt.answerOverride = { _ in false }
            #expect(!SecretsDetector.warnIfNeeded(directory: dir, quiet: true))
            Prompt.answerOverride = { _ in true }
            #expect(SecretsDetector.warnIfNeeded(directory: dir, quiet: true))
            Prompt.answerOverride = { _ in nil }
            #expect(!SecretsDetector.warnIfNeeded(directory: dir, quiet: true))
            Prompt.assumeYes = true
            #expect(SecretsDetector.warnIfNeeded(directory: dir, quiet: true))

            let clean = try sandbox.directory("clean")
            try sandbox.file("clean/a.txt")
            Prompt.assumeYes = false
            Prompt.answerOverride = { _ in false }
            #expect(SecretsDetector.warnIfNeeded(directory: clean, quiet: true))
        }
    }
}
