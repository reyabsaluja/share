import XCTest
@testable import share

final class PackagerTests: XCTestCase {
    func testZipSingleDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("share-pkg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let testFile = tmpDir.appendingPathComponent("hello.txt")
        try "hello world".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let items: [ShareItem] = [.directory(tmpDir)]
        let zipURL = try Packager.zipOnly(items: items, archiveName: "test-archive", outputPath: nil, verbose: false)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        XCTAssertTrue(zipURL.lastPathComponent.hasPrefix("test-archive-"))
        XCTAssertTrue(zipURL.lastPathComponent.hasSuffix(".zip"))
    }

    func testZipWithOutputPath() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("share-pkg-out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let testFile = tmpDir.appendingPathComponent("data.txt")
        try "data".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("output-\(UUID().uuidString).zip").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        let items: [ShareItem] = [.directory(tmpDir)]
        let zipURL = try Packager.zipOnly(items: items, archiveName: nil, outputPath: outputPath, verbose: false)

        XCTAssertEqual(zipURL.path, outputPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }

    func testPackageIfNeededWithFiles() throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("share-pkg-file-\(UUID().uuidString).txt")
        try "content".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let items: [ShareItem] = [.file(tmpFile)]
        let prepared = try Packager.packageIfNeeded(items: items, archiveName: nil, keepTemp: false, verbose: false)

        XCTAssertEqual(prepared.count, 1)
        XCTAssertFalse(prepared[0].packaged)
        XCTAssertEqual(prepared[0].kind, .file)
    }

    func testPackageIfNeededWithDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("share-pkg-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let testFile = tmpDir.appendingPathComponent("test.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let items: [ShareItem] = [.directory(tmpDir)]
        let prepared = try Packager.packageIfNeeded(items: items, archiveName: nil, keepTemp: false, verbose: false)

        XCTAssertEqual(prepared.count, 1)
        XCTAssertTrue(prepared[0].packaged)
        XCTAssertTrue(prepared[0].temporary)

        if case .file(let url) = prepared[0].value {
            XCTAssertTrue(url.path.hasSuffix(".zip"))
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testURLsAreNotPackaged() throws {
        let items: [ShareItem] = [.url(URL(string: "https://apple.com")!)]
        let prepared = try Packager.packageIfNeeded(items: items, archiveName: nil, keepTemp: false, verbose: false)

        XCTAssertEqual(prepared.count, 1)
        XCTAssertFalse(prepared[0].packaged)
        XCTAssertEqual(prepared[0].kind, .url)
    }
}
