# Development

## Layout

```
Sources/ShareCLI/
  Core/         entry point, errors, input resolution, packaging, the Preparer pipeline
  Backends/     AirDrop (NSSharingService), Mail & Messages (AppleScript), Shortcuts, LocalHTTPServer
  Commands/     one file per subcommand; CommonOptions.swift holds shared flags and helpers
  Utilities/    config, aliases, history, git, glob rules, secrets scanner, QR renderer, …
Tests/ShareCLITests/   Swift Testing suite (nested under one serialized root suite)
scripts/smoke.sh       end-to-end --dry-run checks against a built binary
docs/                  user documentation and the generated man page
```

The flow for every sharing command is: `InputResolver.resolve` → `Preparer.prepare` (guards, smart staging, secrets scan, packaging, size limits) → backend `share(_:)` → `Runner.finish` (history, notification, JSON).

## Building

```bash
make debug        # .build/debug/share
make build        # release
make universal    # arm64 + x86_64 fat binary
make install      # PREFIX=/usr/local by default
```

Requires macOS 12+ and a Swift 5.10+ toolchain. Xcode is optional.

## Testing

```bash
make test         # unit tests
make smoke        # builds debug and runs scripts/smoke.sh
```

With only the Command Line Tools installed, XCTest is absent but Swift Testing is bundled; the Makefile adds the framework search paths automatically. On a machine with Xcode, plain `swift test` also works.

Tests never open AirDrop, Mail or Messages. Everything that touches the user's environment is redirected through `Paths.configDirectoryOverride` / `Paths.tempDirectoryOverride` (see `Sandbox` in `TestSupport.swift`) and prompts are answered through `Prompt.answerOverride`.

## Manual verification checklist

The AppleScript and AirDrop paths cannot run headless. Before a release, on a real Mac:

- `share airdrop README.md` opens the picker; cancelling exits 6; a completed transfer exits 0.
- `share email you@example.com README.md` opens a draft with the attachment below the body; `--send` sends.
- `share msg +1… "hi" README.md` opens the conversation with "hi" pre-filled and the file on the clipboard; `--send` delivers both.
- `share serve README.md` link opens from a phone on the same Wi-Fi.
- `share screenshot -s` captures a selection to the clipboard.

## Man page

`make man` runs the swift-argument-parser `generate-manual` plugin and writes `docs/man/share.1`. Regenerate it whenever help text changes; `make install` installs it.

## Releasing

See CONTRIBUTING.md. The `release.yml` workflow builds a universal binary on a tag push and attaches `share-<version>-macos.tar.gz` plus a `.sha256` to the GitHub release.
