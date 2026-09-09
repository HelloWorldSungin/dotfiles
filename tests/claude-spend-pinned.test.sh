#!/usr/bin/env bash
# Behavior tests for the single-owner claude-spend pin. Every case runs the real
# wrapper against a stubbed npx and asserts the argv it would have executed; no
# package is ever fetched or installed.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRAPPER="$ROOT/bin/claude-spend-pinned"
MANIFEST="$ROOT/config/dev-tools-versions.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-spend-pinned-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'

ARGV_LOG="$TMP_ROOT/npx-argv"
STUB_BIN="$TMP_ROOT/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/npx" <<'SH'
#!/usr/bin/env bash
set -eu
: >"$TEST_ARGV_LOG"
for argument in "$@"; do printf '%s\n' "$argument" >>"$TEST_ARGV_LOG"; done
SH
ln -s "$WRAPPER" "$STUB_BIN/claude-spend-pinned"
chmod +x "$STUB_BIN/npx"

# The manifest is the only place a version is read from, here and in the wrapper.
manifest_version() {
  ( set -u; # shellcheck source=/dev/null
    source "$1"; printf '%s\n' "$CLAUDE_SPEND_VERSION" )
}
PINNED_VERSION=$(manifest_version "$MANIFEST")

run_wrapper() {
  local pins=$1
  shift
  rm -f "$ARGV_LOG"
  env PATH="$STUB_BIN:$PATH" DEV_TOOLS_PINS_FILE="$pins" TEST_ARGV_LOG="$ARGV_LOG" \
    CLAUDE_SPEND_NPX_BIN="$STUB_BIN/npx" "$WRAPPER" "$@"
}

argv_line() { sed -n "${1}p" "$ARGV_LOG"; }

# ----------------------------------------- the deployed alias reaches the pin

# The real consumer of the alias is Home Manager: evaluate the generation's own
# `cspend` value rather than reading the Nix source, then execute it.
ALIAS=$(nix eval --raw "$ROOT#homeConfigurations.\"sungin@ct110\".config.programs.zsh.shellAliases.cspend") \
  || fail 'the Home Manager generation does not define a cspend alias'
[ "$ALIAS" = 'claude-spend-pinned' ] || fail "the cspend alias is not the pinned wrapper: $ALIAS"
PACKAGED=$(nix eval --raw "$ROOT#homeConfigurations.\"sungin@ct110\".config.home.packages" \
  --apply 'packages: builtins.concatStringsSep " " (builtins.filter (name: name == "claude-spend-pinned") (map (package: package.name or "") packages))')
[ "$PACKAGED" = 'claude-spend-pinned' ] || fail 'the generation does not put the pinned wrapper on PATH for the alias'

rm -f "$ARGV_LOG"
( export PATH="$STUB_BIN:$PATH" DEV_TOOLS_PINS_FILE="$MANIFEST" TEST_ARGV_LOG="$ARGV_LOG" \
    CLAUDE_SPEND_NPX_BIN="$STUB_BIN/npx"
  eval "$ALIAS" --report ) || fail 'the evaluated cspend alias failed to run'
[ "$(argv_line 1)" = '-y' ] || fail 'the alias invocation dropped the no-prompt npx flag'
[ "$(argv_line 2)" = "claude-spend@$PINNED_VERSION" ] || fail "the alias invocation did not reach npx as claude-spend@$PINNED_VERSION"
[ "$(argv_line 3)" = '--report' ] || fail 'the alias invocation dropped the user argument'
pass 'the deployed cspend alias runs the manifest version and carries no second copy of it'

# ----------------------------------------- the manifest alone moves the version

MUTATED="$TMP_ROOT/mutated-pins.sh"
sed 's/^CLAUDE_SPEND_VERSION=.*/CLAUDE_SPEND_VERSION=9.8.7/' "$MANIFEST" >"$MUTATED"
[ "$(manifest_version "$MUTATED")" = '9.8.7' ] || fail 'the mutated manifest fixture is not what the test assumes'
run_wrapper "$MUTATED" --report || fail 'the wrapper refused a valid mutated pin'
[ "$(argv_line 2)" = 'claude-spend@9.8.7' ] || fail 'bumping the manifest did not change the executed version'
pass 'bumping the manifest alone changes the executed version, with no Nix edit'

# ----------------------------------------- arguments survive verbatim

run_wrapper "$MANIFEST" --since '2026-01-01 09:00' '*.json' 'a"b' "c'd" || fail 'the wrapper refused ordinary arguments'
[ "$(wc -l <"$ARGV_LOG")" -eq 7 ] || fail 'arguments were re-split or dropped on the way to npx'
[ "$(argv_line 4)" = '2026-01-01 09:00' ] || fail 'an argument containing a space was word-split'
[ "$(argv_line 5)" = '*.json' ] || fail 'an argument containing a glob was expanded'
[ "$(argv_line 6)" = 'a"b' ] || fail 'an argument containing a double quote was mangled'
[ "$(argv_line 7)" = "c'd" ] || fail 'an argument containing a single quote was mangled'
pass 'user arguments reach claude-spend verbatim'

# ----------------------------------------- unusable pins fail closed

assert_refused() {
  local label=$1 pins=$2 rc=0
  rm -f "$ARGV_LOG"
  run_wrapper "$pins" --report >"$TMP_ROOT/refusal.out" 2>"$TMP_ROOT/refusal.err" || rc=$?
  [ "$rc" -eq 2 ] || fail "$label did not fail closed (exit $rc)"
  [ ! -e "$ARGV_LOG" ] || fail "$label still invoked npx"
  grep -q 'claude-spend-pinned:' "$TMP_ROOT/refusal.err" || fail "$label refused without a bounded error"
}

MISSING_KEY="$TMP_ROOT/missing-key-pins.sh"
grep -v '^CLAUDE_SPEND_VERSION=' "$MANIFEST" >"$MISSING_KEY"

for bad_version in latest next '' 1.0 1.0.6-beta.1 '1.0.6; echo pwned'; do
  BAD="$TMP_ROOT/bad-pins.sh"
  { cat "$MISSING_KEY"; printf "CLAUDE_SPEND_VERSION='%s'\n" "$bad_version"; } >"$BAD"
  assert_refused "the '$bad_version' pin" "$BAD"
done
pass 'moving, malformed, empty, and unsafe versions are refused before npx runs'

assert_refused 'a manifest with no claude-spend pin' "$MISSING_KEY"

UNREADABLE="$TMP_ROOT/unparseable-pins.sh"
printf 'CLAUDE_SPEND_VERSION=1.0.6\nNPM_TOOL_PINS=(\n' >"$UNREADABLE"
assert_refused 'an unparseable manifest' "$UNREADABLE"

assert_refused 'an absent manifest' "$TMP_ROOT/does-not-exist.sh"
pass 'a missing, keyless, or unparseable manifest never falls back to an unpinned package'

printf '\nall claude-spend-pinned tests passed\n'
