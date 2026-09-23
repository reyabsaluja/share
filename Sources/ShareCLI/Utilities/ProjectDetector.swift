import Foundation

enum ProjectType: String, CaseIterable {
    case node, swift, python, rust, go, ruby, java, dotnet, elixir, php, dart, xcode, unknown
}

/// Guesses the kind of project in a directory so smart mode can skip its build output.
enum ProjectDetector {
    static func detect(at directory: URL? = nil) -> ProjectType {
        let dir = directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return .unknown }
        let names = Set(entries)

        if names.contains("package.json") { return .node }
        if names.contains("Package.swift") { return .swift }
        if names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) { return .xcode }
        if names.contains("Cargo.toml") { return .rust }
        if names.contains("go.mod") { return .go }
        if names.contains("Gemfile") { return .ruby }
        if names.contains("mix.exs") { return .elixir }
        if names.contains("composer.json") { return .php }
        if names.contains("pubspec.yaml") { return .dart }
        if names.contains("requirements.txt") || names.contains("pyproject.toml") || names.contains("setup.py") || names.contains("Pipfile") {
            return .python
        }
        if names.contains("pom.xml") || names.contains("build.gradle") || names.contains("build.gradle.kts") { return .java }
        if names.contains(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".sln") || $0.hasSuffix(".fsproj") }) { return .dotnet }

        return .unknown
    }

    /// Extra ignore patterns for a project type, on top of `ExcludeRules.alwaysExcluded`.
    static func excludes(for type: ProjectType) -> [String] {
        switch type {
        case .node: return [".next", ".nuxt", ".svelte-kit", ".output", "coverage", ".eslintcache", "*.tsbuildinfo"]
        case .swift: return ["Packages", "*.xcuserdatad", "xcuserdata"]
        case .xcode: return ["xcuserdata", "*.xcuserdatad", "*.xcarchive", "Carthage/Build"]
        case .python: return ["*.egg-info", ".tox", ".nox", "htmlcov", ".coverage", ".eggs", "*.pyo", ".ipynb_checkpoints"]
        case .rust: return ["target"]
        case .go: return ["vendor", "*.test"]
        case .ruby: return ["vendor/bundle", ".bundle", "tmp", "log", "coverage"]
        case .java: return [".gradle", "out", "*.class", ".settings", ".classpath", ".project"]
        case .dotnet: return ["bin", "obj", "*.user", ".vs", "packages", "TestResults"]
        case .elixir: return ["_build", "deps", ".elixir_ls", "*.beam"]
        case .php: return ["vendor", ".phpunit.result.cache"]
        case .dart: return [".dart_tool", ".pub-cache", ".flutter-plugins", ".flutter-plugins-dependencies"]
        case .unknown: return []
        }
    }
}
