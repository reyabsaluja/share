import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct SmartRouterTests {
        @Test func emailDetection() {
            #expect(SmartRouter.looksLikeEmail("rey@example.com"))
            #expect(SmartRouter.looksLikeEmail("user+tag@company.co.uk"))
            #expect(!SmartRouter.looksLikeEmail("notanemail"))
            #expect(!SmartRouter.looksLikeEmail("@missing.com"))
            #expect(!SmartRouter.looksLikeEmail("user@"))
            #expect(!SmartRouter.looksLikeEmail("user@host"))
            #expect(!SmartRouter.looksLikeEmail("user@host..com"))
            #expect(!SmartRouter.looksLikeEmail("./file.txt"))
            #expect(!SmartRouter.looksLikeEmail("a b@c.d"))
            #expect(!SmartRouter.looksLikeEmail("https://example.com"))
        }

        @Test func phoneDetection() {
            #expect(SmartRouter.looksLikePhone("+14373459980"))
            #expect(SmartRouter.looksLikePhone("+1 437 345 9980"))
            #expect(SmartRouter.looksLikePhone("(437) 345-9980"))
            #expect(SmartRouter.looksLikePhone("4373459980"))
            #expect(SmartRouter.looksLikePhone("+44 20 7946 0958"))
            #expect(!SmartRouter.looksLikePhone("123"))
            #expect(!SmartRouter.looksLikePhone("hello"))
            #expect(!SmartRouter.looksLikePhone("./file.txt"))
            #expect(!SmartRouter.looksLikePhone("192.168.1.100"))
            #expect(!SmartRouter.looksLikePhone("2026-09-23-123456"))
        }

        @Test func phoneNormalization() {
            #expect(SmartRouter.normalizePhone("+1 (437) 345-9980") == "+14373459980")
            #expect(SmartRouter.normalizePhone("437 345 9980") == "4373459980")
        }

        @Test func detectRoutes() throws {
            let sandbox = try Sandbox()
            _ = sandbox
            #expect(SmartRouter.detect("rey@example.com") == .email("rey@example.com"))
            #expect(SmartRouter.detect("+1 437 345 9980") == .messages("+14373459980"))
            #expect(SmartRouter.detect("airdrop") == .airdrop)
            #expect(SmartRouter.detect("README.md") == nil)
            #expect(SmartRouter.detect(".") == nil)
            #expect(SmartRouter.detect("https://apple.com") == nil)
        }

        @Test func aliasesResolveIncludingGroups() throws {
            let sandbox = try Sandbox()
            _ = sandbox
            try Aliases.set("rey", value: "rey@example.com")
            try Aliases.set("team", value: "rey@example.com, +14375550100")
            #expect(SmartRouter.detect("@rey") == .email("rey@example.com"))
            #expect(SmartRouter.detect("rey") == nil)
            #expect(SmartRouter.detect("rey", allowBareAlias: true) == .email("rey@example.com"))
            #expect(SmartRouter.recipients(from: "@team") == ["rey@example.com", "+14375550100"])
            #expect(SmartRouter.recipients(from: "@team,bob@x.com") == ["rey@example.com", "+14375550100", "bob@x.com"])
        }

        @Test func defaultCommandSplitsRecipientAnywhere() throws {
            let sandbox = try Sandbox()
            let file = try sandbox.file("a.txt")
            let (recipient, items) = DefaultCommand.splitRecipient([file.path, "rey@example.com"])
            #expect(recipient == "rey@example.com")
            #expect(items == [file.path])
            let (none, all) = DefaultCommand.splitRecipient([file.path])
            #expect(none == nil && all == [file.path])
            let (first, rest) = DefaultCommand.splitRecipient(["+14375550100", "hello", "world"])
            #expect(first == "+14375550100" && rest == ["hello", "world"])
        }
    }
}
