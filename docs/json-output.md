# JSON output

Pass `--json` to any command. Exactly one JSON object (or array, for list commands) is written to stdout; human-readable status stays on stderr. The exit code is unchanged.

## Successful share

```json
{
  "ok": true,
  "destination": "email",
  "backend": "Mail.app (AppleScript)",
  "openedNativeUI": true,
  "items": [
    {
      "kind": "file",
      "original": "/Users/rey/Code/app",
      "path": "/private/tmp/share-cli/app-feature-x-2026-09-23-101500.zip",
      "packaged": true,
      "temporary": true,
      "sizeBytes": 48211
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `destination` | `airdrop`, `email`, `messages`, `shortcut`, `serve`, `zip`, `text`, `diff`, `batch`, `screenshot`, `clipboard`, `qr` |
| `backend` | Implementation used (`NSSharingService.sendViaAirDrop`, `Mail.app (AppleScript)`, `Messages.app`, `Shortcuts.app`) |
| `openedNativeUI` | `true` when a draft or picker was left open for the user |
| `items[].kind` | `file`, `url`, `text` |
| `items[].original` | What the user asked for (path, URL, or text preview) |
| `items[].path` / `url` / `text` | What was actually handed to the backend |
| `items[].packaged` | `true` when the item is a zip created by share |
| `items[].temporary` | `true` when the path lives in the scratch directory |
| `items[].sizeBytes` | Size when known |

## Dry run

Same shape with `"dryRun": true` and, for packaged items, an **estimated** `sizeBytes` (the uncompressed total) and the planned archive path. Command-specific details (`subject`, `action`, `recipient`, `url`…) are included as top-level keys.

## Errors

```json
{
  "ok": false,
  "error": {
    "code": "input_not_found",
    "exitCode": 3,
    "message": "no such file or directory: ./missing.txt",
    "hint": "check the path, or quote it if it contains spaces"
  }
}
```

`code` values and exit codes are listed in [exit-codes.md](exit-codes.md). Argument-parsing errors from the CLI framework use `"code": "error"` with exit code 64.

## Command-specific objects

- `share zip --json`: `{ ok, destination: "zip", outputPath, sizeBytes, copiedToClipboard }`
- `share serve --json`: `{ ok, destination: "serve", url, port, file, sizeBytes, copiedToClipboard }` printed once the server is listening
- `share batch --json`: `{ ok, succeeded: [...], failed: [{recipient, error}], items }`; `ok` is false when any recipient failed
- `share preview --json`: array of `{ type, path, name, sizeBytes, fileCount, project, archiveName, sensitive: [{path, reason}], excluded: [...] }`
- `share history --json`: array of `{ timestamp, destination, recipient, items, archivePath, argv, cwd }`
- `share doctor --json`: `{ ok, checks: [{ name, ok, warning, detail }] }`
- `share config --json`: the effective configuration object
- `share alias --json`: `{ name: value }`
- `share clean --json`: `{ ok, dryRun, removed, freedBytes, directory }`
- `share qr --json`: `{ ok, destination: "qr", characters, outputPath?, copiedToClipboard?, opened? }`
