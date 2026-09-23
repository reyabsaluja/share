# Configuration

## Files

| File | Purpose |
|------|---------|
| `~/.config/share/config.json` | Global settings |
| `./.share.json` | Project-local settings, merged over global (each key independently) |
| `~/.config/share/aliases.json` | Aliases (`{"rey": "rey@example.com"}`) |
| `~/.config/share/history.json` | Recent shares |

The config directory moves with `SHARE_CONFIG_DIR`, or `$XDG_CONFIG_HOME/share` when `XDG_CONFIG_HOME` is set. `share config path` prints the active locations.

A malformed file is reported with `warning: ignoring malformed config …` and treated as empty; the command still runs. `share doctor` lists config validity.

## Keys

All keys are optional.

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `smart` | bool | false | Apply smart exclusions to every folder share. Equivalent to passing `--smart` everywhere. |
| `gitignore` | bool | true | In smart mode inside a git repo, use `git ls-files` so `.gitignore` is honored. |
| `from` | string | – | Default sender for `share email` (must be an address configured in Mail). |
| `subjectTemplate` | string | – | Email subject template. Placeholders: `{repo}`, `{branch}`, `{name}` (archive or file name), `{date}` (`YYYY-MM-DD`), `{time}` (`HH:mm`), `{user}`, `{host}`. Empty `()` pairs are removed when the branch is missing. |
| `notify` | bool | false | Post a macOS notification after each successful share and each `share serve` download. |
| `copyZip` | bool | true | Copy the archive path to the clipboard after `share zip`. |
| `color` | bool | auto | Force colored output on or off. |
| `historyLimit` | int | 100 | Entries kept in history. |
| `airdropTimeout` | int | 300 | Seconds to wait for the AirDrop panel. |
| `servePort` | int | random | Fixed port for `share serve`. |
| `skipSecretsScan` | bool | false | Disable the sensitive-file scan. Not recommended. |
| `sms` | bool | false | Use the SMS account (iPhone text relay) for Messages instead of iMessage. |

Legacy names from 0.x are still read: `defaultSmart`, `defaultFrom`, `defaultSubjectTemplate`, `autoNotify`, `autoCopyZip`.

Example:

```json
{
  "smart": true,
  "from": "rey@example.com",
  "subjectTemplate": "{repo} ({branch}) — {date}",
  "notify": true
}
```

## Managing settings

```bash
share config                       # effective settings and where they come from
share config set smart true
share config set from me@x.com --local
share config unset from
share config get subjectTemplate
share config edit                  # $VISUAL / $EDITOR, validated on save
share config keys
```

Booleans accept `true/false`, `yes/no`, `on/off`, `1/0`. Integers must be non-negative; `servePort` must be ≤ 65535.

## Environment variables

| Variable | Effect |
|----------|--------|
| `SHARE_CONFIG_DIR` | Config directory override. |
| `XDG_CONFIG_HOME` | Used as `$XDG_CONFIG_HOME/share` when set. |
| `SHARE_TMPDIR` | Scratch directory for zips, staged copies, screenshots (default `$TMPDIR/share-cli`). |
| `NO_COLOR` | Disable colors ([no-color.org](https://no-color.org)). |
| `CLICOLOR_FORCE` | Force colors even when not a terminal. |
| `TERM=dumb` | Disable colors. |
| `VISUAL`, `EDITOR` | Editor for `share config edit`. |
