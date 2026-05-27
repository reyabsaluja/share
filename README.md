# share

Share files from your Mac terminal via AirDrop, Mail, Messages, and Shortcuts.

```bash
cd ~/Code/my-app
share airdrop
share email teammate@example.com
share shortcut "Upload Build"
```

## Install

### Homebrew

```bash
brew tap derpy82119/tap
brew install share
```

### From source

```bash
git clone https://github.com/derpy82119/share-cli.git
cd share-cli
make
sudo make install
```

## Quick start

```bash
# Share current directory via AirDrop
share airdrop

# Share specific files
share airdrop ./dist/app.zip README.md

# Share a URL
share airdrop https://apple.com

# Create a zip archive
share zip .
share zip . --name my-project --output ~/Desktop/project.zip

# Email files to someone
share email teammate@example.com . --subject "Latest build"

# Run a macOS Shortcut
share shortcut "Send Build" .

# Check system status
share doctor
```

## Commands

| Command | Description |
|---------|-------------|
| `share airdrop` | Share via native AirDrop |
| `share email` | Create a Mail.app draft with attachments |
| `share messages` | Share via Messages |
| `share shortcut` | Run a macOS Shortcut with file input |
| `share zip` | Package files/folders into a zip |
| `share copy` | Copy a path/URL to clipboard |
| `share doctor` | Check macOS integration status |

### Global options

- `--dry-run` — Show what would happen without sharing
- `--json` — Output machine-readable JSON
- `--verbose` — Print detailed output
- `--quiet` — Suppress non-error output

## Safety defaults

- **No path = current directory.** `share airdrop` shares `.`.
- **Draft, never send.** `share email` creates a visible draft. Use `--send` explicitly.
- **No network upload.** Nothing leaves your Mac unless you use a native sharing surface.
- **No silent actions.** AirDrop opens the native picker. Mail opens a visible draft.

## AirDrop limitations

`share airdrop` opens the native AirDrop sharing flow. It does not provide a headless `--to <device>` mode because Apple does not expose nearby AirDrop recipients through a public CLI API.

## Mail/Messages permissions

macOS requires Automation permission for controlling Mail and Messages. If denied:

```
share: Mail automation was denied by macOS.
hint: Open System Settings → Privacy & Security → Automation and allow Terminal to control Mail.
```

## License

MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution of adapted code.
# share
