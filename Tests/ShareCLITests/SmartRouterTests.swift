import XCTest
@testable import share

final class SmartRouterTests: XCTestCase {
    func testEmailDetection() {
        XCTAssertTrue(SmartRouter.looksLikeEmail("rey@example.com"))
        XCTAssertTrue(SmartRouter.looksLikeEmail("user@company.co.uk"))
        XCTAssertTrue(SmartRouter.looksLikeEmail("a@b.io"))
        XCTAssertFalse(SmartRouter.looksLikeEmail("notanemail"))
        XCTAssertFalse(SmartRouter.looksLikeEmail("@missing.com"))
        XCTAssertFalse(SmartRouter.looksLikeEmail("user@"))
        XCTAssertFalse(SmartRouter.looksLikeEmail("./file.txt"))
        XCTAssertFalse(SmartRouter.looksLikeEmail("https://example.com"))
    }

    func testPhoneDetection() {
        XCTAssertTrue(SmartRouter.looksLikePhone("+14373459980"))
        XCTAssertTrue(SmartRouter.looksLikePhone("+1 437 345 9980"))
        XCTAssertTrue(SmartRouter.looksLikePhone("4373459980"))
        XCTAssertTrue(SmartRouter.looksLikePhone("14373459980"))
        XCTAssertFalse(SmartRouter.looksLikePhone("123"))
        XCTAssertFalse(SmartRouter.looksLikePhone("hello"))
        XCTAssertFalse(SmartRouter.looksLikePhone("./file.txt"))
        XCTAssertFalse(SmartRouter.looksLikePhone("192.168.1.100"))
    }

    func testSmartRouting() {
        if case .email(let addr) = SmartRouter.detect("rey@example.com") {
            XCTAssertEqual(addr, "rey@example.com")
        } else {
            XCTFail("Should detect email")
        }

        if case .messages(let num) = SmartRouter.detect("+14373459980") {
            XCTAssertEqual(num, "+14373459980")
        } else {
            XCTFail("Should detect phone")
        }

        XCTAssertNil(SmartRouter.detect("README.md"))
        XCTAssertNil(SmartRouter.detect("."))
        XCTAssertNil(SmartRouter.detect("./src"))
        XCTAssertNil(SmartRouter.detect("https://apple.com"))
    }
}
