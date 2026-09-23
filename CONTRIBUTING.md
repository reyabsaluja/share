# Contributing

Thanks for helping make `share` better. This is a small, focused tool; the bar for changes is "does it make sharing from the terminal safer or faster on macOS?"

## Setup

```bash
git clone https://github.com/reyabsaluja/share.git
cd share
make debug     # builds .build/debug/share
make test      # runs the Swift Testing suite
make smoke     # end-to-end checks with --dry-run (no AirDrop/Mail/Messages UI)
```

Xcode is not required. With only the Command Line Tools, `make test` adds the framework paths Swift Testing needs.

## Ground rules

- **Safety defaults are not negotiable.** Drafts stay drafts unless `--send`. Nothing leaves the machine except through the app the user named. Secrets scanning stays on by default.
- **Every sharing command goes through `Preparer.prepare`.** That is where the guards, smart staging, secrets scan and packaging live. Do not reimplement them in a command.
- **stdout is for results, stderr is for status.** `--json` must produce exactly one JSON object on stdout.
- **Errors are `ShareError`s** with a hint. New failure modes get a new case, a unique exit code and a line in `docs/exit-codes.md`.
- **Tests for logic, smoke tests for wiring.** Pure logic (globbing, routing, packaging, config) gets a unit test. Command wiring gets a `--dry-run` line in `scripts/smoke.sh`.
- Keep AppleScript minimal and pass values as `argv`, never by string interpolation.

## Adding a command

1. Create `Sources/ShareCLI/Commands/<Name>Command.swift` using `@OptionGroup var output: OutputOptions` (and `PackagingOptions` if it packages).
2. Call `output.apply()` first, resolve inputs with `InputResolver`, prepare with `Preparer`, and finish with `Runner.finish` so history, notifications and JSON stay consistent.
3. Register it in `ShareCommand.configuration.subcommands`.
4. Document it in `docs/commands.md` and the README table, add smoke coverage, and regenerate the man page with `make man`.

## Releasing

1. Bump `Version.current` in `Sources/ShareCLI/Core/Version.swift` and add a `CHANGELOG.md` entry.
2. `make test && make smoke && make man`.
3. Commit, tag `vX.Y.Z`, push the tag. The release workflow builds a universal binary and attaches `share-X.Y.Z-macos.tar.gz` with its SHA-256.
4. Update `Formula/share.rb` with the new tag and checksum.

## Commit messages

Short imperative subject (`fix: honor --smart in zip`), body explaining why when it is not obvious.
