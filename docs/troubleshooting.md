# Troubleshooting

Run `share doctor` first; it checks AirDrop, apps, tools, config validity and completions. `share doctor --automation` also tests Mail and Messages permissions.

## "Mail automation was denied by macOS" (exit 7)

macOS asked whether your terminal may control Mail/Messages and the answer was no, or the prompt never appeared.

1. System Settings → Privacy & Security → Automation.
2. Find your terminal (Terminal, iTerm, Warp, VS Code…) and enable Mail and/or Messages.
3. If the app is not listed, run `share doctor --automation` to trigger the prompt again. Deleting the entry with `tccutil reset AppleEvents` also resets it.

## Messages: "could not find the recipient" (exit 9)

`--send` uses your iMessage account. The recipient must be reachable via iMessage (blue bubble). Use the full number with country code (`+14375550100`) or the exact iMessage email. For SMS via iPhone relay use `--sms` (Text Message Forwarding must be enabled on the iPhone).

Drafts (without `--send`) open the conversation via the `sms:` URL scheme; if Messages opens without the text, update macOS or use `--send`.

## AirDrop panel does not appear / exits with "timed out" (exit 10)

- Wi-Fi and Bluetooth must be on; `share doctor` shows "AirDrop unavailable" otherwise.
- The panel is attached to a tiny invisible window; if another app is full-screen, switch to the desktop.
- Increase `airdropTimeout` or `--timeout` for large transfers.

## Screenshot fails immediately

Grant Screen Recording to your terminal: System Settings → Privacy & Security → Screen Recording. Cancelling the crosshair with Esc exits 6, which is expected.

## "refusing to share sensitive files in non-interactive mode" (exit 6)

The secrets scan found something and there is no terminal to ask on (CI, cron, an agent). Options: `--smart` (drops `.env` and friends), `.shareignore`, `--yes` to proceed anyway, or `skipSecretsScan` in config.

## "refusing to package your entire home directory" (exit 12)

You ran `share` from `~`. `cd` into a project or name the files explicitly. `--yes` overrides for the home directory; the filesystem root is never packaged.

## The zip contains files I excluded

`--smart` is required for the exclusion rules (or `smart: true` in config). `--exclude` alone applies only your patterns plus `.git` and `.DS_Store`. `share preview . --smart --all` lists exactly what is dropped.

## Colors or emoji look wrong

`--no-color`, `NO_COLOR=1`, or `share config set color false`. Piped output has colors disabled automatically.

## Completions do not work

`share completions --install`, then restart the shell. For zsh make sure `~/.zsh/completions` is in `fpath` before `compinit`. For bash install `bash-completion@2` via Homebrew.

## Where are the temporary files?

`$TMPDIR/share-cli` (or `SHARE_TMPDIR`). They are pruned after 24 hours at every run; `share clean --all` removes them now. Drafts reference attachments from there, so send or discard drafts before cleaning.

## Reporting a bug

Include `share --version`, `share doctor --json`, the exact command with `--verbose`, and the macOS version. Redact recipients and paths as needed.
