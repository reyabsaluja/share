import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct PackagerTests {
        @Test func singleDirectoryZipUnpacksToNamedFolder() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("project")
            try sandbox.file("project/hello.txt", "hello world")

            let zip = try Packager.zipOnly(items: [.directory(dir)], archiveName: "test-archive", outputPath: nil, verbose: false)
            #expect(zip.lastPathComponent.hasPrefix("test-archive-"))
            #expect(zip.lastPathComponent.hasSuffix(".zip"))
            #expect(zip.path.hasPrefix(sandbox.temp.path))
            let entries = Sandbox.zipEntries(zip)
            #expect(entries.contains("project/hello.txt"))
            #expect(!entries.contains { $0.contains("__MACOSX") || $0.contains("/._") })
        }

        @Test func bundleUnpacksToArchiveNameNotUUID() throws {
            let sandbox = try Sandbox()
            let a = try sandbox.directory("a")
            let b = try sandbox.directory("b")
            try sandbox.file("a/1.txt")
            try sandbox.file("b/2.txt")
            let loose = try sandbox.file("notes.md", "# notes")

            let prepared = try Packager.packageIfNeeded(items: [.directory(a), .directory(b), .file(loose)], archiveName: nil, verbose: false)
            #expect(prepared.count == 1)
            #expect(prepared[0].packaged && prepared[0].temporary)
            let entries = Sandbox.zipEntries(prepared[0].fileURL!)
            #expect(entries.contains("share-bundle/a/1.txt"))
            #expect(entries.contains("share-bundle/b/2.txt"))
            #expect(entries.contains("share-bundle/notes.md"))
        }

        @Test func duplicateNamesInBundleAreDisambiguated() throws {
            let sandbox = try Sandbox()
            let one = try sandbox.file("x/report.txt", "1")
            let two = try sandbox.file("y/report.txt", "2")
            let dir = try sandbox.directory("z")
            let prepared = try Packager.packageIfNeeded(items: [.file(one), .file(two), .directory(dir)], archiveName: "pack", verbose: false)
            let entries = Sandbox.zipEntries(prepared[0].fileURL!)
            #expect(entries.contains("pack/report.txt"))
            #expect(entries.contains("pack/report-2.txt"))
        }

        @Test func filesUrlsAndTextPassThrough() throws {
            let sandbox = try Sandbox()
            let file = try sandbox.file("a.txt", "content")
            let prepared = try Packager.packageIfNeeded(items: [.file(file), .url(URL(string: "https://apple.com")!), .text("hi")], archiveName: nil, verbose: false)
            #expect(prepared.count == 3)
            #expect(prepared.allSatisfy { !$0.packaged })
            #expect(prepared[0].sizeBytes == 7)
            #expect(prepared[1].kind == .url)
            #expect(prepared[2].kind == .text)
        }

        @Test func outputPathMayBeDirectoryAndRefusesClobber() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("src")
            try sandbox.file("src/a.txt")
            let outDir = try sandbox.directory("out")

            let zip = try Packager.zipOnly(items: [.directory(dir)], archiveName: nil, outputPath: outDir.path, verbose: false)
            #expect(zip.path == outDir.appendingPathComponent("src.zip").path)
            #expect(FileManager.default.fileExists(atPath: zip.path))

            #expect(throws: ShareError.self) {
                _ = try Packager.zipOnly(items: [.directory(dir)], archiveName: nil, outputPath: outDir.path, verbose: false)
            }
            let again = try Packager.zipOnly(items: [.directory(dir)], archiveName: nil, outputPath: outDir.path, overwrite: true, verbose: false)
            #expect(again.path == zip.path)

            let noExt = try Packager.zipOnly(items: [.directory(dir)], archiveName: nil, outputPath: outDir.appendingPathComponent("custom").path, verbose: false)
            #expect(noExt.lastPathComponent == "custom.zip")
        }

        @Test func defaultArchiveNames() throws {
            let sandbox = try Sandbox()
            let file = try sandbox.file("report.pdf")
            let dir = try sandbox.directory("proj")
            #expect(Packager.defaultArchiveName(for: [.file(file)]) == "report")
            #expect(Packager.defaultArchiveName(for: [.directory(dir)]) == "proj")
            #expect(Packager.defaultArchiveName(for: [.file(file), .directory(dir)]) == Packager.bundleName)
        }

        @Test func zipOnlyRejectsNonFiles() {
            #expect(throws: ShareError.self) {
                _ = try Packager.zipOnly(items: [.url(URL(string: "https://x.com")!)], archiveName: nil, outputPath: nil, verbose: false)
            }
        }

        @Test func dateSlugFormat() {
            let slug = DateSlug.current()
            #expect(slug.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil)
        }
    }
}
