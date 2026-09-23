import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct GlobTests {
        @Test func parsesPatternFlags() {
            let plain = IgnorePattern(line: "node_modules")!
            #expect(!plain.anchored && !plain.directoryOnly && !plain.negated)

            let dir = IgnorePattern(line: "build/")!
            #expect(dir.directoryOnly && dir.pattern == "build")

            let anchored = IgnorePattern(line: "/dist")!
            #expect(anchored.anchored && anchored.pattern == "dist")

            let nested = IgnorePattern(line: "docs/*.pdf")!
            #expect(nested.anchored)

            let negated = IgnorePattern(line: "!keep.log")!
            #expect(negated.negated && negated.pattern == "keep.log")

            #expect(IgnorePattern(line: "# comment") == nil)
            #expect(IgnorePattern(line: "   ") == nil)
            #expect(IgnorePattern(line: "**/cache")!.anchored == false)
        }

        @Test func matchesBasenameAtAnyDepth() {
            let patterns = Glob.parse(["*.log", "node_modules"])
            #expect(Glob.isIgnored(relativePath: "a/b/c.log", isDirectory: false, patterns: patterns))
            #expect(Glob.isIgnored(relativePath: "node_modules", isDirectory: true, patterns: patterns))
            #expect(Glob.isIgnored(relativePath: "pkg/node_modules/x/index.js", isDirectory: false, patterns: patterns))
            #expect(!Glob.isIgnored(relativePath: "src/main.swift", isDirectory: false, patterns: patterns))
        }

        @Test func anchoredPatternsOnlyMatchFromRoot() {
            let patterns = Glob.parse(["/dist", "docs/*.pdf"])
            #expect(Glob.isIgnored(relativePath: "dist", isDirectory: true, patterns: patterns))
            #expect(Glob.isIgnored(relativePath: "dist/app.js", isDirectory: false, patterns: patterns))
            #expect(!Glob.isIgnored(relativePath: "packages/dist", isDirectory: true, patterns: patterns))
            #expect(Glob.isIgnored(relativePath: "docs/guide.pdf", isDirectory: false, patterns: patterns))
            #expect(!Glob.isIgnored(relativePath: "other/docs/guide.pdf", isDirectory: false, patterns: patterns))
        }

        @Test func directoryOnlyPatterns() {
            let patterns = Glob.parse(["build/"])
            #expect(Glob.isIgnored(relativePath: "build", isDirectory: true, patterns: patterns))
            #expect(!Glob.isIgnored(relativePath: "build", isDirectory: false, patterns: patterns))
            #expect(Glob.isIgnored(relativePath: "build/out.o", isDirectory: false, patterns: patterns))
        }

        @Test func negationReincludesAndLastMatchWins() {
            let patterns = Glob.parse(["*.log", "!important.log"])
            #expect(Glob.isIgnored(relativePath: "debug.log", isDirectory: false, patterns: patterns))
            #expect(!Glob.isIgnored(relativePath: "important.log", isDirectory: false, patterns: patterns))
            // Cannot re-include inside an excluded directory.
            let nested = Glob.parse(["logs", "!logs/keep.txt"])
            #expect(Glob.isIgnored(relativePath: "logs/keep.txt", isDirectory: false, patterns: nested))
        }

        @Test func builtInRulesCoverTheUsualSuspects() {
            let rules = ExcludeRules(lines: ExcludeRules.alwaysExcluded)
            for path in [".git/HEAD", "node_modules/a/b.js", ".env", ".env.production", ".DS_Store", "target/debug/x", "app.log"] {
                #expect(rules.isExcluded(relativePath: path, isDirectory: false), "\(path) should be excluded")
            }
            for path in ["src/main.swift", ".env.example", "README.md", "environment.ts"] {
                #expect(!rules.isExcluded(relativePath: path, isDirectory: false), "\(path) should be kept")
            }
        }

        @Test func shareIgnoreFileIsRead() throws {
            let sandbox = try Sandbox()
            let dir = try sandbox.directory("proj")
            try sandbox.file("proj/.shareignore", "# comment\n*.tmp\nsecret/\n")
            let rules = ExcludeRules.smart(for: dir)
            #expect(rules.isExcluded(relativePath: "a.tmp", isDirectory: false))
            #expect(rules.isExcluded(relativePath: "secret", isDirectory: true))
            #expect(!rules.isExcluded(relativePath: "secret", isDirectory: false))
        }
    }
}
