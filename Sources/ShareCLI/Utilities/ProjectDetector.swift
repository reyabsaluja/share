import Foundation

enum ProjectType {
    case node
    case swift
    case python
    case rust
    case go
    case ruby
    case java
    case unknown
}

enum ProjectDetector {
    static func detect(at directory: URL? = nil) -> ProjectType {
        let dir = directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fm = FileManager.default

        if fm.fileExists(atPath: dir.appendingPathComponent("package.json").path) { return .node }
        if fm.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return .swift }
        if fm.fileExists(atPath: dir.appendingPathComponent("Cargo.toml").path) { return .rust }
        if fm.fileExists(atPath: dir.appendingPathComponent("go.mod").path) { return .go }
        if fm.fileExists(atPath: dir.appendingPathComponent("Gemfile").path) { return .ruby }
        if fm.fileExists(atPath: dir.appendingPathComponent("requirements.txt").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent("pyproject.toml").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent("setup.py").path) { return .python }
        if fm.fileExists(atPath: dir.appendingPathComponent("pom.xml").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent("build.gradle").path) { return .java }

        return .unknown
    }

    static func excludes(for type: ProjectType) -> Set<String> {
        var base: Set<String> = [".git", ".DS_Store"]

        switch type {
        case .node:
            base.formUnion(["node_modules", ".next", ".nuxt", "dist", ".cache", ".parcel-cache", "coverage"])
        case .swift:
            base.formUnion([".build", ".swiftpm", "DerivedData", "Packages"])
        case .python:
            base.formUnion(["__pycache__", ".pytest_cache", ".mypy_cache", "venv", ".venv", ".tox", "*.egg-info", "dist", "build"])
        case .rust:
            base.formUnion(["target"])
        case .go:
            base.formUnion(["vendor"])
        case .ruby:
            base.formUnion(["vendor/bundle", ".bundle", "tmp"])
        case .java:
            base.formUnion(["target", "build", ".gradle", "out"])
        case .unknown:
            break
        }

        base.formUnion([".env", ".env.local", ".env.production", ".env.development"])
        return base
    }
}
