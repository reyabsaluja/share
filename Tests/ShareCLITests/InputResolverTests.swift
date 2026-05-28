import XCTest
@testable import share

final class InputResolverTests: XCTestCase {
    func testEmptyArgumentsDefaultsToCurrentDirectory() throws {
        let items = try InputResolver.resolve([])
        XCTAssertEqual(items.count, 1)
        if case .directory(let url) = items[0] {
            XCTAssertEqual(url.path, FileManager.default.currentDirectoryPath)
        } else {
            XCTFail("Expected directory item")
        }
    }

    func testURLDetection() {
        XCTAssertTrue(InputResolver.isURL("http://example.com"))
        XCTAssertTrue(InputResolver.isURL("https://example.com"))
        XCTAssertTrue(InputResolver.isURL("HTTPS://EXAMPLE.COM"))
        XCTAssertTrue(InputResolver.isURL("mailto:test@example.com"))
        XCTAssertFalse(InputResolver.isURL("./file.txt"))
        XCTAssertFalse(InputResolver.isURL("/usr/local/bin"))
        XCTAssertFalse(InputResolver.isURL("relative/path"))
    }

    func testURLResolution() throws {
        let items = try InputResolver.resolve(["https://apple.com"])
        XCTAssertEqual(items.count, 1)
        if case .url(let url) = items[0] {
            XCTAssertEqual(url.absoluteString, "https://apple.com")
        } else {
            XCTFail("Expected URL item")
        }
    }

    func testNonExistentPathThrows() {
        XCTAssertThrowsError(try InputResolver.resolve(["./nonexistent-file-abc123.txt"])) { error in
            guard let shareError = error as? ShareError else {
                XCTFail("Expected ShareError")
                return
            }
            if case .inputNotFound = shareError {
                // expected
            } else {
                XCTFail("Expected inputNotFound error")
            }
        }
    }

    func testExistingFileResolution() throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("share-test-\(UUID().uuidString).txt")
        try "test".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let items = try InputResolver.resolve([tmpFile.path])
        XCTAssertEqual(items.count, 1)
        if case .file(let url) = items[0] {
            XCTAssertEqual(url.path, tmpFile.path)
        } else {
            XCTFail("Expected file item")
        }
    }

    func testDirectoryResolution() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("share-test-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let items = try InputResolver.resolve([tmpDir.path])
        XCTAssertEqual(items.count, 1)
        if case .directory(let url) = items[0] {
            XCTAssertEqual(url.path, tmpDir.path)
        } else {
            XCTFail("Expected directory item")
        }
    }

    func testMultipleInputs() throws {
        let tmpFile1 = FileManager.default.temporaryDirectory.appendingPathComponent("share-multi-1-\(UUID().uuidString).txt")
        let tmpFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("share-multi-2-\(UUID().uuidString).txt")
        try "a".write(to: tmpFile1, atomically: true, encoding: .utf8)
        try "b".write(to: tmpFile2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tmpFile1)
            try? FileManager.default.removeItem(at: tmpFile2)
        }

        let items = try InputResolver.resolve([tmpFile1.path, "https://example.com", tmpFile2.path])
        XCTAssertEqual(items.count, 3)
    }
}
