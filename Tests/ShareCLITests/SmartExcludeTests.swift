import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct SmartExcludeTests {
        private func makeProject(_ sandbox: Sandbox) throws -> URL {
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/package.json", "{}")
            try sandbox.file("proj/src/index.js", "console.log(1)")
            try sandbox.file("proj/node_modules/lib/index.js", "junk")
            try sandbox.file("proj/.env", "SECRET=1")
            try sandbox.file("proj/.env.example", "SECRET=")
            try sandbox.file("proj/debug.log", "x")
            try sandbox.file("proj/.shareignore", "*.tmp\n")
            try sandbox.file("proj/scratch.tmp", "x")
            try sandbox.file("proj/.git/HEAD", "ref: refs/heads/main")
            return dir
        }

        @Test func stagingAppliesRules() throws {
            let sandbox = try Sandbox()
            let dir = try makeProject(sandbox)
            let staged = try SmartExclude.stage(directory: dir, useGit: false, verbose: false)
            #expect(staged.url.lastPathComponent == "proj")
            #expect(staged.projectType == .node)
            #expect(!staged.usedGit)
            let fm = FileManager.default
            #expect(fm.fileExists(atPath: staged.url.appendingPathComponent("src/index.js").path))
            #expect(fm.fileExists(atPath: staged.url.appendingPathComponent(".env.example").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent("node_modules").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent(".env").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent("debug.log").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent("scratch.tmp").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent(".git").path))
            #expect(staged.copiedFiles == 4)
        }

        @Test func planCountsWithoutCopying() throws {
            let sandbox = try Sandbox()
            let dir = try makeProject(sandbox)
            let plan = SmartExclude.plan(directory: dir)
            #expect(plan.included == 4)
            #expect(plan.excluded.contains("node_modules"))
            #expect(plan.excluded.contains(".env"))
            #expect(plan.excluded.contains("scratch.tmp"))
        }

        @Test func symlinksEscapingTheTreeAreSkipped() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/a.txt")
            let outside = try sandbox.file("outside.txt", "secret")
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.txt"), withDestinationURL: outside)
            let staged = try SmartExclude.stage(directory: dir, useGit: false, verbose: false)
            #expect(FileManager.default.fileExists(atPath: staged.url.appendingPathComponent("a.txt").path))
            #expect(!FileManager.default.fileExists(atPath: staged.url.appendingPathComponent("link.txt").path))
        }

        @Test func gitRepositoriesHonorGitignore() throws {
            let sandbox = try Sandbox()
            guard GitContext.isAvailable else { return }
            let dir = try sandbox.directory("repo")
            let initResult = Sandbox.git(dir, "init", "-q", "-b", "main")
            guard initResult.status == 0 else { return }
            try sandbox.file("repo/.gitignore", "generated/\n*.bak\n")
            try sandbox.file("repo/src/main.swift", "print(1)")
            try sandbox.file("repo/generated/out.txt", "x")
            try sandbox.file("repo/notes.bak", "x")
            try sandbox.file("repo/untracked.md", "new")
            Sandbox.git(dir, "add", ".")
            Sandbox.git(dir, "commit", "-q", "-m", "init")

            #expect(GitContext.isRepoRoot(dir))
            #expect(GitContext.archiveName(for: dir) == "repo")
            Sandbox.git(dir, "checkout", "-q", "-b", "feature/x")
            #expect(GitContext.archiveName(for: dir) == "repo-feature-x")

            let staged = try SmartExclude.stage(directory: dir, verbose: false)
            #expect(staged.usedGit)
            let fm = FileManager.default
            #expect(fm.fileExists(atPath: staged.url.appendingPathComponent("src/main.swift").path))
            #expect(fm.fileExists(atPath: staged.url.appendingPathComponent("untracked.md").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent("generated").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent("notes.bak").path))
            #expect(!fm.fileExists(atPath: staged.url.appendingPathComponent(".git").path))
        }

        @Test func projectDetection() throws {
            let sandbox = try Sandbox()
            let node = try sandbox.directory("n"); try sandbox.file("n/package.json", "{}")
            let rust = try sandbox.directory("r"); try sandbox.file("r/Cargo.toml", "")
            let py = try sandbox.directory("p"); try sandbox.file("p/pyproject.toml", "")
            let xcode = try sandbox.directory("x"); try sandbox.directory("x/App.xcodeproj")
            let dotnet = try sandbox.directory("d"); try sandbox.file("d/App.csproj", "")
            #expect(ProjectDetector.detect(at: node) == .node)
            #expect(ProjectDetector.detect(at: rust) == .rust)
            #expect(ProjectDetector.detect(at: py) == .python)
            #expect(ProjectDetector.detect(at: xcode) == .xcode)
            #expect(ProjectDetector.detect(at: dotnet) == .dotnet)
            #expect(ProjectDetector.detect(at: sandbox.root) == .unknown)
            #expect(ProjectDetector.excludes(for: .python).contains("*.egg-info"))
        }

        @Test func directoryStatsRespectRulesAndLimits() throws {
            let sandbox = try Sandbox()
            let dir = try makeProject(sandbox)
            let raw = DirectoryStats.measure(dir)
            #expect(raw.fileCount == 9)
            let filtered = DirectoryStats.measure(dir, rules: ExcludeRules.smart(for: dir))
            #expect(filtered.fileCount == 4)
            let capped = DirectoryStats.measure(dir, fileLimit: 2)
            #expect(capped.truncated && capped.fileCount == 2)
            #expect(capped.summary.hasPrefix("over "))
        }
    }
}
