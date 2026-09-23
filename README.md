# share

Share files from your Mac's terminal: AirDrop, Mail, Messages, Shortcuts, or a scannable local link.

```bash
share                       # AirDrop the current folder (zipped, secrets checked)
share rey@example.com       # draft an email with the folder attached
share +14375550100 "hi"     # open a Message
share @team ./report.pdf    # alias → one or many recipients
share serve ./build.dmg     # local link + QR code for any phone on the Wi-Fi
```

Everything stays on your Mac. Nothing is uploaded to a third party, drafts are never sent without `--send`, and folders are scanned for credentials before they leave.

- [Install](#install)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Smart routing](#smart-routing)
- [Smart mode: leaving out the junk](#smart-mode-leaving-out-the-junk)
- [Safety defaults](#safety-defaults)
- [Configuration](#configuration)
- [Scripting and JSON](#scripting-and-json)
- [Documentation](#documentation)
- [Requirements and permissions](#requirements-and-permissions)
- [Development](#development)

## Install

**From source** (macOS 12+, Swift 5.10+ toolchain; Xcode or the Command Line Tools):

```bash
git clone https://github.com/reyabsaluja/share.git
cd share
make
sudo make install          # installs to /usr/local/bin/share (+ man page)
share completions --install
```

**Homebrew** (from the formula in this repo):

```bash
brew install --formula ./Formula/share.rb
```

**Prebuilt binary**: every [GitHub release](https://github.com/reyabsaluja/share/releases) ships a universal (Apple silicon + Intel) `share-<version>-macos.tar.gz`. Unpack it and move `share` somewhere on your `PATH`.

Then run `share init` for a guided setup (aliases, defaults, completions) and `share doctor` to confirm everything is wired up.

## Quick start

```bash
# AirDrop
share                                  # current directory → zip → AirDrop picker
share airdrop ./dist/app.zip README.md # several files
share airdrop . --smart                # skip .git, node_modules, build output, .env…
share airdrop --clipboard              # whatever is on the clipboard (image, text, file)

# Email (opens a Mail.app draft; add --send to send right away)
share email teammate@example.com . --subject "Latest build"
share email @rey ./report.pdf --cc boss@example.com --body "As discussed."
git log -5 | share email @rey --subject "Recent commits"   # stdin becomes the body

# Messages
share messages +14375550100 ./photo.heic "Here you go"
share msg @rey "on my way" --send

# Local link with QR code (no AirDrop, no cloud)
share serve ./video.mov --once          # stop after the first download
share serve . --smart --timeout 300

# Everything else
share zip . --smart -o ~/Desktop        # zip to a folder, path copied to clipboard
share diff @rey --staged                # send the git diff (inline or as a .patch)
share screenshot @rey -s                # capture a selection and message it
share qr https://example.com            # QR code in the terminal
share text "meeting moved to 3pm" --to @team
share batch @rey,bob@x.com,+15550100 ./notes.md
share preview . --smart                 # what would be shared, before sharing
share again                             # repeat the last share
```

## Commands

| Command | What it does |
|---------|--------------|
| `share airdrop` (`ad`, `drop`) | Open the AirDrop picker with the items. Folders are zipped. |
| `share email` (`mail`) | Create a Mail.app draft with attachments; `--send` sends. |
| `share messages` (`msg`, `sms`) | Open a Messages conversation with text and files; `--send` sends. |
| `share serve` (`link`) | Serve one file on the LAN with a random-token URL and a QR code. |
| `share shortcut` (`sc`) | Run a macOS Shortcut with the items as input (`--list` to browse). |
| `share zip` | Create a zip; `--smart`, `--exclude`, `--output`, `--force`. |
| `share copy` (`cp`) | Copy a path, `file://` URL, file contents, or the file itself. |
| `share text` | Share a snippet from args, stdin, or the clipboard. |
| `share diff` | Share the git diff (`--staged`, `--range main..HEAD`, `--attach`). |
| `share batch` | One payload, many recipients. |
| `share qr` | QR code in the terminal, or as PNG (`--output`, `--copy`, `--open`). |
| `share screenshot` (`ss`) | Capture full screen, selection (`-s`) or window (`-w`) and share it. |
| `share open` | Open in the default app or reveal in Finder. |
| `share preview` (`ls`) | Sizes, project type, exclusions and sensitive files, before sharing. |
| `share again` | Re-run the last share (or `--index N`). |
| `share history` | Recent shares. |
| `share alias` | Manage `@name` recipients, including groups. |
| `share config` | View and change settings. |
| `share completions` | Print or `--install` zsh/bash/fish completions. |
| `share init` | Guided setup. |
| `share clean` | Remove scratch files (zips, staged copies, screenshots). |
| `share doctor` | Check AirDrop, apps, tools, config and (optionally) automation permissions. |

Every sharing command accepts:

| Flag | Meaning |
|------|---------|
| `--dry-run` | Explain what would happen and stop. Nothing is copied, zipped or opened. |
| `--json` | Machine-readable result on stdout (errors too). |
| `--smart` | Exclude VCS metadata, dependencies, build output and secrets. |
| `--exclude <pattern>` | Extra gitignore-style pattern (repeatable). |
| `--no-zip` | Share folders as-is instead of zipping. |
| `--name <name>` | Archive name. |
| `--yes` / `-y` | Answer yes to every confirmation. |
| `--quiet` / `-q`, `--verbose` / `-v` | Less or more output on stderr. |
| `--color` / `--no-color` | Force colors on or off (`NO_COLOR` is respected). |

Run `share <command> --help` for the full list. The man page (`man share`) covers every command.

## Smart routing

Without a subcommand, `share` looks at the arguments and picks the destination:

| First non-file argument | Destination |
|-------------------------|-------------|
| nothing / paths only | AirDrop |
| `name@host.tld` | Email |
| `+1 437 555 0100`, `4375550100` | Messages |
| `@alias` or a bare alias name | Whatever the alias points to |
| `a@x.com,@bob,+1555…` or a group alias | Batch (everyone gets the same items) |
| `airdrop` | AirDrop |

The recipient can appear anywhere: `share README.md @rey` and `share @rey README.md` are the same. Paths that do not exist are reported as errors, never guessed.

Aliases live in `~/.config/share/aliases.json`:

```bash
share alias rey rey@example.com
share alias team "rey@example.com, bob@example.com, +14375550100"
share alias                     # list
share alias rey --remove
```

## Smart mode: leaving out the junk

`--smart` (or `share config set smart true`) makes a filtered copy of each folder before zipping:

1. **Built-in rules** drop `.git`, `node_modules`, `.build`, `target`, `dist`, `__pycache__`, `.env*`, `.DS_Store`, logs, IDE folders, and more.
2. **Project rules** are added for the detected project type (Node, Swift, Xcode, Python, Rust, Go, Ruby, Java, .NET, Elixir, PHP, Dart).
3. **`.gitignore`** is honored automatically inside a git repository via `git ls-files` (tracked plus untracked-but-not-ignored files). Turn off with `share config set gitignore false`.
4. **`.shareignore`** in the folder adds project-specific rules with gitignore syntax (`*.log`, `build/`, `/dist`, `!keep.txt`).
5. **`--exclude`** adds one-off patterns on the command line.

`share preview . --smart` shows exactly what would be dropped. `.env.example`-style files are kept.

## Safety defaults

- **Draft, never send.** Email and Messages open a draft you can review. `--send` is always explicit.
- **Nothing leaves the Mac** except through the native app you asked for. `share serve` binds to your local network only, uses a random token in the URL, serves one file, and stops on Ctrl-C, timeout, or `--once`.
- **Secrets are checked first.** Folders are scanned for credential files (`.env`, `id_rsa`, `*.pem`, `credentials.json`, …) and for token-shaped contents (AWS, GitHub, Slack, Stripe, Google, Anthropic, OpenAI keys, private-key blocks). You are asked before they go anywhere; in scripts the share is refused unless `--yes`.
- **No accidental mega-archives.** Packaging `/`, `/Users`, or your home folder is refused, and folders over 1 GB or 50 000 files prompt first.
- **Clean zips.** Archives unpack to a single folder, without `__MACOSX` or `._` files.
- **Exit codes mean something.** See [docs/exit-codes.md](docs/exit-codes.md).

## Configuration

Settings merge from `~/.config/share/config.json` and a project-local `./.share.json` (local wins). Manage them with `share config`:

```bash
share config set smart true
share config set from me@example.com
share config set subjectTemplate "{repo} ({branch}) — {date}"
share config set notify true
share config --local set smart false   # per-project override
share config                            # show effective settings
share config keys                       # every key with a description
```

| Key | Type | Effect |
|-----|------|--------|
| `smart` | bool | Apply smart exclusions to every folder share. |
| `gitignore` | bool | Honor `.gitignore` in smart mode (default true). |
| `from` | string | Default sender for email. |
| `subjectTemplate` | string | Email subject template: `{repo}` `{branch}` `{name}` `{date}` `{time}` `{user}` `{host}`. |
| `notify` | bool | macOS notification after each successful share. |
| `copyZip` | bool | Copy the archive path after `share zip` (default true). |
| `color` | bool | Force colors on or off. |
| `historyLimit` | int | History entries to keep (default 100). |
| `airdropTimeout` | int | Seconds to wait for the AirDrop panel (default 300). |
| `servePort` | int | Fixed port for `share serve`. |
| `skipSecretsScan` | bool | Disable the sensitive-file scan (not recommended). |
| `sms` | bool | Use the SMS account for Messages instead of iMessage. |

Environment: `SHARE_CONFIG_DIR` relocates the config directory (also honors `XDG_CONFIG_HOME`), `SHARE_TMPDIR` relocates scratch files, `NO_COLOR` / `CLICOLOR_FORCE` control colors.

## Scripting and JSON

Add `--json` to any command for a single JSON object on stdout; status messages stay on stderr. Errors are JSON too:

```bash
$ share email @rey ./report.pdf --json --yes
{ "ok": true, "destination": "email", "backend": "Mail.app (AppleScript)", "openedNativeUI": true,
  "items": [ { "kind": "file", "path": "/…/report.pdf", "packaged": false, "sizeBytes": 48211 } ] }

$ share airdrop ./missing.txt --json; echo $?
{ "ok": false, "error": { "code": "input_not_found", "exitCode": 3, "message": "no such file or directory: ./missing.txt", "hint": "…" } }
3
```

Piped stdin becomes the email body or message text (`git log | share email @rey`). Prompts are answered on `/dev/tty`, so piping and confirmations coexist; without a terminal, anything that needs confirmation is refused unless `--yes`.

See [docs/json-output.md](docs/json-output.md) for the schema.

## Documentation

- [docs/commands.md](docs/commands.md): every command, option and example
- [docs/configuration.md](docs/configuration.md): config files, keys, environment variables
- [docs/smart-mode.md](docs/smart-mode.md): exclusion rules, `.shareignore`, secrets scanning
- [docs/serve.md](docs/serve.md): how the local link works and its security model
- [docs/json-output.md](docs/json-output.md): JSON schema for automation
- [docs/exit-codes.md](docs/exit-codes.md): exit codes and error codes
- [docs/troubleshooting.md](docs/troubleshooting.md): permissions, AirDrop, Messages, common errors
- [docs/development.md](docs/development.md): building, testing, releasing
- [CHANGELOG.md](CHANGELOG.md)

## Requirements and permissions

- macOS 12 Monterey or later, Apple silicon or Intel.
- **Automation**: the first time Mail or Messages is driven, macOS asks whether your terminal may control the app. If you declined once, re-enable it under System Settings → Privacy & Security → Automation. `share doctor --automation` tests it.
- **Screen Recording** is needed for `share screenshot` on recent macOS versions.
- **AirDrop** opens the native picker; Apple exposes no API to choose a device from the command line, so there is no `--to <device>`.
- **Messages drafts** use the `sms:` URL scheme (Messages has no scripting command for an unsent message). Text is pre-filled; files are put on the clipboard for a single ⌘V. `--send` delivers text and files directly.

## Development

```bash
make debug       # .build/debug/share
make test        # Swift Testing (works with Xcode or just the Command Line Tools)
make smoke       # end-to-end dry-run checks against the debug binary
make man         # regenerate docs/man/share.1
make universal   # arm64 + x86_64 release build
```

See [docs/development.md](docs/development.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for adapted code.
