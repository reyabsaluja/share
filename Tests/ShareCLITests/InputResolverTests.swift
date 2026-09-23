import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct InputResolverTests {
        @Test func emptyArgumentsMeanCurrentDirectory() throws {
            let items = try InputResolver.resolve([])
            #expect(items.count == 1)
            guard case .directory(let url) = items[0] else { Issue.record("expected directory"); return }
            #expect(url.path == FileManager.default.currentDirectoryPath)
        }

        @Test func urlDetection() {
            #expect(InputResolver.isURL("http://example.com"))
            #expect(InputResolver.isURL("HTTPS://EXAMPLE.COM"))
            #expect(InputResolver.isURL("mailto:test@example.com"))
            #expect(!InputResolver.isURL("./file.txt"))
            #expect(!InputResolver.isURL("relative/path"))
        }

        @Test func urlResolution() throws {
            let items = try InputResolver.resolve(["https://apple.com"])
            #expect(items == [.url(URL(string: "https://apple.com")!)])
        }

        @Test func invalidURLThrows() {
            #expect(throws: ShareError.self) { try InputResolver.resolve(["https://"]) }
        }

        @Test func missingPathThrowsInputNotFound() {
            do {
                _ = try InputResolver.resolve(["./nonexistent-file-abc123.txt"])
                Issue.record("expected an error")
            } catch let error as ShareError {
                guard case .inputNotFound = error else { Issue.record("wrong error \(error)"); return }
                #expect(error.exitCode == 3)
            } catch {
                Issue.record("wrong error type")
            }
        }

        @Test func filesAndDirectoriesResolve() throws {
            let sandbox = try Sandbox()
            let file = try sandbox.file("a.txt")
            let dir = try sandbox.directory("d")
            let items = try InputResolver.resolve([file.path, dir.path, "https://example.com"])
            #expect(items.count == 3)
            #expect(items[0] == .file(file.standardized))
            #expect(items[1] == .directory(dir.standardized))
        }

        @Test func tildeAndRelativePathsExpand() {
            let home = InputResolver.expandPath("~")
            #expect(home.path == FileManager.default.homeDirectoryForCurrentUser.standardized.path)
            let rel = InputResolver.expandPath("./x/../y")
            #expect(rel.path == URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("y").path)
        }

        @Test func existsAsFileIgnoresURLsAndDash() {
            #expect(!InputResolver.existsAsFile("https://example.com"))
            #expect(!InputResolver.existsAsFile("-"))
        }
    }
}
