#!/usr/bin/env bash
# End-to-end checks that never open AirDrop, Mail or Messages: everything runs with
# --dry-run or against local state in an isolated config/scratch directory.
#
# Usage: scripts/smoke.sh [path-to-share-binary]
set -euo pipefail

SHARE="${1:-.build/debug/share}"
[ -x "$SHARE" ] || { echo "binary not found: $SHARE (run 'make debug')"; exit 1; }
SHARE="$(cd "$(dirname "$SHARE")" && pwd)/$(basename "$SHARE")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SHARE_CONFIG_DIR="$WORK/config" SHARE_TMPDIR="$WORK/tmp" NO_COLOR=1
mkdir -p "$WORK/config" "$WORK/tmp"

pass=0; fail=0
check() {  # check <description> <expected-exit> <command...>
  local desc="$1" expected="$2"; shift 2
  local out; local rc=0
  out="$("$@" 2>&1 </dev/null)" || rc=$?
  if [ "$rc" = "$expected" ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf '  FAIL %s (exit %s, expected %s)\n%s\n' "$desc" "$rc" "$expected" "$out"
  fi
}
expect_output() {  # expect_output <description> <substring> <command...>
  local desc="$1" needle="$2"; shift 2
  local out
  out="$("$@" 2>&1 </dev/null)" || true
  if [[ "$out" == *"$needle"* ]]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf '  FAIL %s (missing %q)\n%s\n' "$desc" "$needle" "$out"
  fi
}

# Fixture project
PROJ="$WORK/proj"
mkdir -p "$PROJ/src" "$PROJ/node_modules/lib"
echo '{}' > "$PROJ/package.json"
echo 'console.log(1)' > "$PROJ/src/index.js"
echo 'junk' > "$PROJ/node_modules/lib/index.js"
echo 'SECRET=1' > "$PROJ/.env"
echo 'ok' > "$PROJ/README.md"
cd "$PROJ"

echo "share smoke tests ($SHARE)"
check "version" 0 "$SHARE" --version
check "help" 0 "$SHARE" --help
check "unknown flag is rejected" 2 "$SHARE" . --bogus
check "missing path" 3 "$SHARE" airdrop ./nope.txt
expect_output "json error" '"input_not_found"' "$SHARE" airdrop ./nope.txt --json
expect_output "airdrop dry run mentions secrets" "sensitive" "$SHARE" airdrop --dry-run
check "airdrop dry run json" 0 "$SHARE" airdrop --dry-run --json
check "zip refuses secrets non-interactively" 6 "$SHARE" zip . -o "$WORK/raw.zip" --no-copy
check "airdrop dry run smart" 0 "$SHARE" airdrop . --smart --dry-run
expect_output "smart routing to email" "Would email → rey@example.com" "$SHARE" rey@example.com README.md --dry-run
expect_output "recipient anywhere" "Would email → rey@example.com" "$SHARE" README.md rey@example.com --dry-run
expect_output "smart routing to messages" "Would messages → +14375550100" "$SHARE" "+1 (437) 555-0100" hello --dry-run
check "alias set" 0 "$SHARE" alias rey rey@example.com
check "group alias set" 0 "$SHARE" alias team "rey@example.com,+14375550100"
check "alias invalid value" 2 "$SHARE" alias bad notanaddress
expect_output "alias list" "@team" "$SHARE" alias
expect_output "bare alias routes" "Would email → rey@example.com" "$SHARE" rey README.md --dry-run
expect_output "group alias fans out" "Would batch" "$SHARE" @team README.md --dry-run
check "alias remove" 0 "$SHARE" alias rey --remove
check "email dry run" 0 "$SHARE" email rey@example.com README.md --dry-run --subject Hi
check "email rejects non-address" 2 "$SHARE" email nope README.md --dry-run
check "messages dry run" 0 "$SHARE" msg +14375550100 README.md "hello" --dry-run
check "batch dry run" 0 "$SHARE" batch rey@example.com,+14375550100 README.md --dry-run
check "text dry run" 0 "$SHARE" text hello world --dry-run
check "text to alias dry run" 0 "$SHARE" text hello --to rey@example.com --dry-run
check "zip to file" 0 "$SHARE" zip src -o "$WORK/src.zip" --no-copy
check "zip refuses overwrite" 12 "$SHARE" zip src -o "$WORK/src.zip" --no-copy
check "zip --force" 0 "$SHARE" zip src -o "$WORK/src.zip" --no-copy --force
check "zip smart drops the secrets so no prompt is needed" 0 "$SHARE" zip . --smart -o "$WORK/proj.zip" --no-copy
if unzip -Z1 "$WORK/proj.zip" | grep -q node_modules; then fail=$((fail+1)); echo "  FAIL smart zip still contains node_modules"; else pass=$((pass+1)); echo "  ok   smart zip excludes node_modules"; fi
if unzip -Z1 "$WORK/proj.zip" | grep -q '\.env$'; then fail=$((fail+1)); echo "  FAIL smart zip still contains .env"; else pass=$((pass+1)); echo "  ok   smart zip excludes .env"; fi
mkdir -p "$WORK/out"
check "zip to directory" 0 "$SHARE" zip src -o "$WORK/out" --no-copy
[ -f "$WORK/out/src.zip" ] && { pass=$((pass+1)); echo "  ok   zip landed in directory"; } || { fail=$((fail+1)); echo "  FAIL zip did not land in directory"; }
check "zip json" 0 "$SHARE" zip src --json --no-copy
check "copy dry run" 0 "$SHARE" copy README.md --dry-run
check "preview" 0 "$SHARE" preview . --smart --all
check "preview json" 0 "$SHARE" preview . --json
check "qr to file" 0 "$SHARE" qr https://example.com -o "$WORK/qr.png"
check "qr print" 0 "$SHARE" qr hello --print
check "qr empty" 2 "$SHARE" qr
check "serve dry run" 0 "$SHARE" serve README.md --dry-run
check "serve rejects url" 8 "$SHARE" serve https://example.com
check "screenshot dry run" 0 "$SHARE" screenshot --dry-run
check "open dry run" 0 "$SHARE" open README.md --dry-run
check "shortcut needs name" 2 "$SHARE" shortcut
check "config show" 0 "$SHARE" config
check "config set" 0 "$SHARE" config set smart true
check "config bad key" 11 "$SHARE" config set bogus 1
check "config bad value" 11 "$SHARE" config set historyLimit abc
expect_output "config get" "true" "$SHARE" config get smart
check "config unset" 0 "$SHARE" config unset smart
check "config keys" 0 "$SHARE" config keys
check "history" 0 "$SHARE" history
check "history json" 0 "$SHARE" history --json
check "again dry run" 0 "$SHARE" again --dry-run
check "clean dry run" 0 "$SHARE" clean --dry-run
check "clean all" 0 "$SHARE" clean --all
check "doctor" 0 "$SHARE" doctor
check "doctor json" 0 "$SHARE" doctor --json
check "completions zsh" 0 "$SHARE" completions zsh
check "completions bash" 0 "$SHARE" completions bash
check "completions fish" 0 "$SHARE" completions fish
check "completions bad shell" 2 "$SHARE" completions bogus
check "home directory refused" 12 env HOME="$HOME" sh -c "cd \"\$HOME\" && \"$SHARE\" airdrop --dry-run"
check "root refused" 12 "$SHARE" airdrop / --dry-run
check "init needs a terminal" 2 "$SHARE" init

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
