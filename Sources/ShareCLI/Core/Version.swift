import Foundation

/// The single source of truth for the CLI version string.
///
/// Bump this (and `CHANGELOG.md`) when cutting a release. The Homebrew formula
/// and the GitHub release workflow read the git tag, which must match.
enum Version {
    static let current = "1.0.0"
}
