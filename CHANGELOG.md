# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-23

First production release.

### Added
- `share serve`: serve one file on the local network with a random-token URL and a terminal QR code. Supports HEAD, range requests, `--once`, `--timeout`, `--port`, `--host`.
- `share config`: `get`, `set`, `unset`, `path`, `edit`, `keys`, with `--local` for per-project `.share.json`.
- Group aliases (`share alias team "a@x.com,b@y.com"`) that fan out through `share batch`.
- Bare alias names (`share rey file.txt`) and recipients anywhere on the command line (`share file.txt @rey`).
- `.gitignore` support in smart mode via `git ls-files`; `.shareignore` now uses full gitignore syntax (anchors, `dir/`, negation).
- `--exclude <pattern>` on every packaging command.
- Content-based secrets detection (AWS, GitHub, GitLab, Slack, Stripe, Google, Anthropic, OpenAI, npm, SendGrid, Hugging Face tokens, private-key blocks) on top of file-name rules.
- Guards against packaging `/`, `/Users`, or the home directory, and a size prompt for folders over 1 GB / 50 000 files.
- `share qr` renders in the terminal by default (`--print`, `--scale`, `--correction`).
- `share airdrop --clipboard` shares clipboard images, text or files.
- `share diff`: `--range`, path filters, `.patch` attachments for long diffs, AirDrop destination.
- `share copy`: `--file` (paste the file itself), `--contents`, `--smart`.
- `share screenshot --save`, `share open --app`, `share history --all`, `share again --index`.
- `share doctor --automation` to test Mail/Messages permissions; config validity, aliases and completions checks.
- `--json` errors with stable `code` values and documented exit codes.
- `--color` / `--no-color`, `NO_COLOR`, `CLICOLOR_FORCE`, `TERM=dumb` handling.
- `SHARE_CONFIG_DIR`, `XDG_CONFIG_HOME`, `SHARE_TMPDIR` environment overrides.
- Config keys: `gitignore`, `notify`, `copyZip`, `color`, `historyLimit`, `airdropTimeout`, `servePort`, `skipSecretsScan`, `sms`, `subjectTemplate` (with `{repo}` `{branch}` `{name}` `{date}` `{time}` `{user}` `{host}`).
- Man page, shell completions with alias suggestions, GitHub Actions CI and release workflows, Homebrew formula, smoke-test script.
- A Swift Testing suite (70 tests) covering routing, globbing, staging, packaging, secrets, config, history, aliases, QR and the HTTP server.

### Changed
- Messages automation rewritten for the current scripting dictionary (`participant` / `account`); the old `buddy` / `service` script no longer works on modern macOS.
- Messages drafts now open the conversation with the text pre-filled (via the `sms:` URL scheme) and put files on the clipboard instead of just activating the app.
- `share diff` and `share batch` no longer send Messages immediately; `--send` is required, matching every other command.
- Archives no longer contain `__MACOSX` or `._` AppleDouble files, and bundles unpack to a folder named after the archive instead of a UUID.
- Archive names are derived from the shared directory (and its git branch), not from whatever directory the command ran in.
- Email: URLs and text arguments become part of the body instead of being dropped; `--body -` and `--body-file` read the body from stdin or a file; `--from` falls back to config; comma-separated `--cc` / `--bcc`.
- Dry runs no longer create zips or staged copies.
- Secrets scan runs on the filtered tree, so files that smart mode removes no longer trigger a warning.
- The sensitive-file prompt reads from `/dev/tty`, so piping a body and confirming coexist.
- Stdin is only read when data is actually available, so the CLI cannot hang when launched with an idle pipe.
- History records the exact command line and working directory; `share again` replays it faithfully.
- Exit codes are now honored (previously every error exited 1) and `--json` reports errors as JSON.
- Legacy config keys (`defaultSmart`, `defaultFrom`, `autoNotify`, `autoCopyZip`, `defaultSubjectTemplate`) still load; malformed config files produce a warning instead of being silently ignored.
- Automation-denied detection recognizes the actual macOS error (`-1743`, "Not authorized").
- AirDrop cancellations exit with the "cancelled" code instead of a packaging error.
- Tests migrated from XCTest to Swift Testing so they run with only the Command Line Tools installed.

### Fixed
- `share zip --smart` ignored smart mode.
- `share zip --output` silently overwrote existing files; now refuses without `--force` and accepts a directory.
- Flags after smart-routed arguments (`share . --smart`) were silently dropped.
- `share again` failed when `share` was invoked through `$PATH`.
- `share email` had no `--yes`, so oversized attachments could not be confirmed in scripts.
- Phone detection matched date-like strings and IP addresses.
- Wrong repository URLs in the README.

## [0.1.0] - 2026-09-01

Initial release: AirDrop, email, Messages, Shortcuts, zip, copy, text, diff, batch, QR, screenshot, open, preview, again, history, alias, completions, init, clean, doctor.

[1.0.0]: https://github.com/reyabsaluja/share/releases/tag/v1.0.0
[0.1.0]: https://github.com/reyabsaluja/share/releases/tag/v0.1.0
