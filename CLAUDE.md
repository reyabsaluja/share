# share (macOS CLI, Swift)

Swift Package; executable target `share` in `Sources/ShareCLI`, tests in `Tests/ShareCLITests` (Swift Testing, one serialized root suite).

## Build and test
- `make debug` → `.build/debug/share`; `make build` for release; `make universal` for a fat binary.
- `make test` runs the unit tests. This machine has only the Command Line Tools (no Xcode), so XCTest is unavailable; the Makefile passes the framework search paths Swift Testing needs. Plain `swift test` fails here.
- `make smoke` runs `scripts/smoke.sh` (end-to-end `--dry-run` checks in an isolated `SHARE_CONFIG_DIR`/`SHARE_TMPDIR`).
- `make man` regenerates `docs/man/share.1` via the argument-parser plugin.

## Architecture rules
- Every sharing command: `InputResolver.resolve` → `Preparer.prepare` → backend → `Runner.finish`. Guards, smart staging, secrets scan and packaging live only in `Preparer`.
- Errors are `ShareError` cases with unique exit codes (`docs/exit-codes.md`); the custom `@main` in `Core/Main.swift` prints them (JSON when `--json`).
- stdout = results only; status goes through `Log` to stderr.
- Never test AirDrop/Mail/Messages live; use `--dry-run`. AppleScript syntax can be checked with `osacompile`.
- Messages scripting uses `participant … of (1st account whose service type = iMessage)`; `buddy`/`service` no longer exist on modern macOS.

## Docs
README.md is the entry point; `docs/` holds per-topic pages. Keep `CHANGELOG.md` and `Version.current` in sync when releasing.
