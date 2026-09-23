# Command reference

Every command supports `--help`. Options shared by the sharing commands are listed once under [Common options](#common-options).

## Common options

| Option | Description |
|--------|-------------|
| `--dry-run` | Print what would happen and exit 0. No files are created, no apps are opened. |
| `--json` | One JSON object on stdout (see [json-output.md](json-output.md)). |
| `-v`, `--verbose` | Timing and detail on stderr. |
| `-q`, `--quiet` | Suppress status output. Errors still print. |
| `-y`, `--yes` | Answer yes to confirmations (secrets found, large folder, oversized email). |
| `--color`, `--no-color` | Force colors on or off. |
| `-n`, `--name <name>` | Archive name without `.zip`. Default: folder name plus git branch. |
| `--smart` | Apply exclusion rules (see [smart-mode.md](smart-mode.md)). |
| `--exclude <pattern>` | Extra gitignore-style pattern. Repeatable. Implies a filtered copy. |
| `--no-zip` | Share folders as-is. |

Positional items may be files, directories, `http(s)://` and `mailto:` URLs, or `-` for stdin text. With no items the current directory is used.

## share (smart routing)

```
share [recipient] [items…] [options]
```

Picks a destination from the arguments (see README → Smart routing). Accepts all common options plus `--subject`, `--body`, `--from`, `--cc`, `--bcc`, `--send`, `--sms`. Unknown flags are rejected rather than ignored.

## share airdrop

```
share airdrop [items…] [--clipboard] [--timeout <s>]
```

Opens the AirDrop picker. One folder becomes `<name>-<timestamp>.zip`; several folders or folders mixed with files become one bundle. Files and URLs cannot travel in the same AirDrop payload, so mixed sets are offered one item at a time.

- `--clipboard`: share the clipboard. Images become PNGs, text becomes a `.txt`, a copied file is shared directly, a copied URL is sent as a link.
- `--timeout`: seconds to wait for the panel (default `airdropTimeout` config, else 300).

Cancelling the picker exits with code 6.

## share email

```
share email <to> [items…] [-s subject] [-b body|-] [--body-file f] [--from a] [--cc a,b] [--bcc a] [--send]
```

Creates a visible Mail.app draft. `<to>` may be an address, `@alias`, or comma-separated list. Piped stdin is appended to the body. URLs and text items go into the body; files are attached. Attachments over 25 MB prompt (or are refused without a terminal unless `--yes`). The default subject is `Shared: <repo> (<branch>)` or the `subjectTemplate` from config.

## share messages

```
share messages <recipient> [text|items…] [-t text|-] [--send] [--sms]
```

Arguments that are not existing files become the message text. Without `--send` the conversation opens with the text pre-filled and files on the clipboard (⌘V attaches them). With `--send`, text and every file are sent immediately through the iMessage account (`--sms` or the `sms` config key uses the SMS account). Recipients are phone numbers or iMessage email addresses; formatting like `(437) 555-0100` is normalized.

## share serve

```
share serve [items…] [-p port] [--once] [--timeout <s>] [--no-qr] [--no-copy] [--host h]
```

Serves one file (folders and multiple items are zipped first) at `http://<lan-ip>:<port>/<token>/<file>`. Prints the URL, a QR code (when stdout is a terminal) and copies the URL to the clipboard. Stops on Ctrl-C, after `--timeout` seconds (default 600, 0 = never), or after the first complete download with `--once`. See [serve.md](serve.md).

## share shortcut

```
share shortcut <name> [items…] [-o output]      share shortcut --list
```

Runs a Shortcut once per item: files via the shortcut's file input, URLs and text via stdin. With several items and `-o`, outputs are numbered `name-1.ext`, `name-2.ext`.

## share zip

```
share zip [items…] [-n name] [-o path|dir] [--smart] [--exclude p] [--force] [--no-copy]
```

Without `-o` the archive lands in the scratch directory and its path is printed (and copied to the clipboard unless `--no-copy` or `copyZip=false`). `-o` may be an existing directory or a file path (`.zip` is appended when missing). Existing files are never overwritten without `--force`.

## share copy

```
share copy [item] [--zip] [--file-url] [--file] [--contents] [--smart] [-n name]
```

Default: the absolute path. `--file-url`: `file://` URL. `--file`: the file object (paste into Finder, Mail, Slack). `--contents`: the file's text. `--zip`: zip first, then copy the archive path (or the archive itself with `--file`).

## share text

```
share text [words…] [-t recipient] [-s subject] [--clipboard] [--send]
```

Reads text from arguments, stdin, or `--clipboard`. Without `--to`, copies to the clipboard. With `--to`, drafts an email, opens Messages, or (for `airdrop`) AirDrops a `.txt`.

## share diff

```
share diff <recipient|airdrop> [paths…] [--staged] [--range rev] [-s subject] [--attach] [--send]
```

Shares `git diff` output. Email gets the diff inline when it is under 400 lines, otherwise a `.patch` attachment (`--attach` forces it). Messages and AirDrop always get a `.patch` file. Fails with a usage error when there are no changes.

## share batch

```
share batch <r1,r2,…> [items…] [-s subject] [-b body] [--send]
```

Packages once, then drafts (or sends) to every recipient. Failures for one recipient do not stop the others; the exit code is non-zero only when everyone failed. Smart routing does this automatically for comma lists and group aliases.

## share qr

```
share qr [text…] [-p] [-o file.png] [--copy] [--open] [--scale n] [--correction L|M|Q|H]
```

Prints a scannable QR code in the terminal (black-on-white ANSI so it works on any theme). When stdout is not a terminal and no output flag is given, the PNG is copied to the clipboard. Max ~2900 bytes of content.

## share screenshot

```
share screenshot [recipient|airdrop] [-s] [-w] [-d seconds] [--save path] [--keep] [--send] [--subject s]
```

Captures the screen (silently), a selection (`-s`) or a window (`-w`), then copies it to the clipboard or shares it with the recipient. Requires Screen Recording permission on recent macOS.

## share open

```
share open [items…] [-r] [-a app]
```

Opens items in their default app, reveals them in Finder (`-r`), or opens them with a named app.

## share preview

```
share preview [items…] [--smart] [--exclude p] [--all]
```

Shows sizes, file counts, project type, git branch and dirty state, what smart mode would exclude, and sensitive files that would still be shared. `--json` gives the same as data.

## share again

```
share again [--dry-run] [-i N]
```

Re-runs the recorded command line of the last share (or the Nth most recent) in its original working directory. Dry runs are never recorded.

## share history

```
share history [-c N] [--all] [--json] [--clear]
```

## share alias

```
share alias                    share alias <name> <value>
share alias <name>             share alias <name> --remove
```

Values are validated: each comma-separated part must be an email, phone number, or existing alias.

## share config

```
share config [--json]          share config get <key>
share config set <key> <v>     share config unset <key>       (add --local for ./.share.json)
share config path              share config edit              share config keys
```

## share completions

```
share completions [zsh|bash|fish] [--install]
```

Defaults to `$SHELL`. Completions suggest `@aliases` for recipient arguments.

## share init

Interactive setup: aliases, smart mode default, sender address, completions. Needs a terminal.

## share clean

```
share clean [--all] [--older-than hours] [--dry-run] [--json]
```

Scratch files older than 24 hours are pruned automatically at every run; `share clean` removes them on demand.

## share doctor

```
share doctor [--json] [--automation]
```

Exits non-zero when a required component is missing. `--automation` sends a harmless AppleScript query to Mail and Messages to check permissions (macOS may show a prompt).
