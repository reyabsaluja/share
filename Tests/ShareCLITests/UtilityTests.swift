import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct UtilityTests {
        @Test func humanReadableSizes() {
            #expect(HumanReadable.fileSize(0) == "0 B")
            #expect(HumanReadable.fileSize(1023) == "1023 B")
            #expect(HumanReadable.fileSize(1024) == "1.0 KB")
            #expect(HumanReadable.fileSize(1_572_864) == "1.5 MB")
            #expect(HumanReadable.fileSize(5 * 1024 * 1024 * 1024) == "5.0 GB")
            #expect(HumanReadable.count(1, "file") == "1 file")
            #expect(HumanReadable.count(2, "entry", "entries") == "2 entries")
            #expect(HumanReadable.duration(0.5) == "500 ms")
            #expect(HumanReadable.duration(90) == "1m 30s")
        }

        @Test func subjectTemplateRendersVariables() {
            let date = Date(timeIntervalSince1970: 0)
            let rendered = SubjectTemplate.render("{name} on {date} by {user}", itemName: "report.pdf", date: date)
            #expect(rendered.hasPrefix("report.pdf on 19"))
            #expect(rendered.contains(NSUserName()))
            #expect(!rendered.contains("{"))
            #expect(SubjectTemplate.render("x ()", itemName: nil) == "x")
        }

        @Test func branchSanitization() {
            #expect(GitContext.sanitize("feature/cool stuff") == "feature-cool-stuff")
            #expect(GitContext.sanitize("v1.2_x") == "v1.2_x")
            #expect(GitContext.isDefaultBranch("main") && GitContext.isDefaultBranch("master") && !GitContext.isDefaultBranch("dev"))
        }

        @Test func errorsHaveDistinctCodesAndHints() {
            let errors: [ShareError] = [
                .usage("u"), .inputNotFound("p"), .packagingFailed("x"), .backendUnavailable("b"), .userCancelled,
                .automationDenied(app: "Mail"), .unsupported("u"), .sharingFailed("s"), .timeout("t"), .configError("c"), .refused("r"),
            ]
            let codes = errors.map(\.exitCode)
            #expect(Set(codes).count == codes.count)
            #expect(errors.allSatisfy { !$0.code.isEmpty && !$0.description.isEmpty })
            #expect(ShareError.invalidURL("x").exitCode == 2)
            #expect(ShareError.automationDenied(app: "Mail").hint?.contains("Automation") == true)
        }

        @Test func jsonErrorOutput() throws {
            let text = JSONOutput.error(.inputNotFound("./x"))
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            #expect(object?["ok"] as? Bool == false)
            let error = object?["error"] as? [String: Any]
            #expect(error?["code"] as? String == "input_not_found")
            #expect(error?["exitCode"] as? Int == 3)
        }

        @Test func mailBodyComposition() {
            let url = PreparedShareItem(kind: .url, originalDescription: "u", value: .url(URL(string: "https://x.com")!), packaged: false, temporary: false, sizeBytes: nil)
            let text = PreparedShareItem(kind: .text, originalDescription: "t", value: .text("note"), packaged: false, temporary: false, sizeBytes: nil)
            #expect(MailBackend.composeBody("hi", items: [url, text], hasAttachments: false) == "hi\n\nhttps://x.com\nnote")
            #expect(MailBackend.composeBody(nil, items: [], hasAttachments: true) == "\n\n")
            #expect(MailBackend.composeBody("x", items: [], hasAttachments: true) == "x\n\n")
        }

        @Test func shortcutIndexedOutputs() {
            #expect(ShortcutsBackend.indexedOutput("/tmp/out.txt", index: 0) == "/tmp/out-1.txt")
            #expect(ShortcutsBackend.indexedOutput("/tmp/out", index: 2) == "/tmp/out-3")
        }

        @Test func automationDenialDetection() {
            #expect(AppleScriptRunner.isAutomationDenied("execution error: Not authorized to send Apple events to Mail. (-1743)"))
            #expect(AppleScriptRunner.isAutomationDenied("Something is not allowed"))
            #expect(!AppleScriptRunner.isAutomationDenied("Can’t get participant"))
        }

        @Test func tempFilePruning() throws {
            let sandbox = try Sandbox()
            let old = sandbox.temp.appendingPathComponent("old.zip")
            let fresh = sandbox.temp.appendingPathComponent("fresh.zip")
            try "a".write(to: old, atomically: true, encoding: .utf8)
            try "b".write(to: fresh, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 24 * 3600)], ofItemAtPath: old.path)
            TempFiles.pruneOld()
            #expect(!FileManager.default.fileExists(atPath: old.path))
            #expect(FileManager.default.fileExists(atPath: fresh.path))
        }

        @Test func privateAddressDetection() {
            #expect(NetworkInfo.isPrivate("192.168.1.4"))
            #expect(NetworkInfo.isPrivate("10.0.0.1"))
            #expect(NetworkInfo.isPrivate("172.20.0.1"))
            #expect(!NetworkInfo.isPrivate("172.32.0.1"))
            #expect(!NetworkInfo.isPrivate("100.64.0.1"))
            #expect(!NetworkInfo.isPrivate("nope"))
        }
    }
}
