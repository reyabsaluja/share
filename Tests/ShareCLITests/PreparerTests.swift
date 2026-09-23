import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct PreparerTests {
        @Test func refusesDangerousRoots() {
            #expect(throws: ShareError.self) { try Preparer.guardDangerousRoots([.directory(URL(fileURLWithPath: "/"))]) }
            #expect(throws: ShareError.self) { try Preparer.guardDangerousRoots([.directory(Paths.home)]) }
            Prompt.assumeYes = true
            defer { Prompt.assumeYes = false }
            #expect(throws: Never.self) { try Preparer.guardDangerousRoots([.directory(Paths.home)]) }
            #expect(throws: ShareError.self) { try Preparer.guardDangerousRoots([.directory(URL(fileURLWithPath: "/"))]) }
        }

        @Test func dryRunPlansWithoutCreatingFiles() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/a.txt", "12345")
            var options = PrepareOptions(destination: "airdrop")
            options.dryRun = true
            let prepared = try Preparer.prepare([.directory(dir)], options: options)
            #expect(prepared.count == 1)
            #expect(prepared[0].packaged)
            #expect(prepared[0].sizeBytes == 5)
            #expect(prepared[0].fileURL?.lastPathComponent.hasPrefix("proj-") == true)
            #expect(!FileManager.default.fileExists(atPath: prepared[0].fileURL!.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.temp.path).isEmpty)
        }

        @Test func smartStagingIsAppliedEvenWithNoZip() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/a.txt")
            try sandbox.file("proj/node_modules/x.js")
            var options = PrepareOptions(destination: "airdrop")
            options.smart = true
            options.noZip = true
            let prepared = try Preparer.prepare([.directory(dir)], options: options)
            let staged = prepared[0].fileURL!
            #expect(staged.path != dir.path)
            #expect(!FileManager.default.fileExists(atPath: staged.appendingPathComponent("node_modules").path))
            #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("a.txt").path))
        }

        @Test func secretsAbortWhenDeclined() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/.env", "X=1")
            Prompt.answerOverride = { _ in false }
            var options = PrepareOptions(destination: "airdrop")
            options.quiet = true
            #expect(throws: ShareError.self) { try Preparer.prepare([.directory(dir)], options: options) }

            options.smart = true  // .env is excluded by smart mode, so no prompt
            let prepared = try Preparer.prepare([.directory(dir)], options: options)
            #expect(prepared.count == 1 && prepared[0].packaged)
        }

        @Test func emailLimitPromptsAndCanBeAccepted() throws {
            let sandbox = try Sandbox()
            let big = sandbox.temp.appendingPathComponent("big.bin")
            let handle = try { () -> FileHandle in
                FileManager.default.createFile(atPath: big.path, contents: nil)
                return try FileHandle(forWritingTo: big)
            }()
            try handle.truncate(atOffset: UInt64(Preparer.emailLimit + 1))
            try handle.close()

            var options = PrepareOptions(destination: "email")
            options.quiet = true
            Prompt.answerOverride = { _ in false }
            #expect(throws: ShareError.self) { try Preparer.prepare([.file(big)], options: options) }
            Prompt.answerOverride = { _ in true }
            #expect(try Preparer.prepare([.file(big)], options: options).count == 1)
            options.destination = "airdrop"
            Prompt.answerOverride = { _ in false }
            #expect(try Preparer.prepare([.file(big)], options: options).count == 1)
        }
    }
}
