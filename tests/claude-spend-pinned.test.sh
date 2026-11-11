#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-spend-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'
STUB_BIN="$TMP_ROOT/bin"
ARGV_LOG="$TMP_ROOT/npx-argv"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
[ "$1" = view ] || exit 1
case "$2" in
  claude-spend@latest) version=${TEST_LATEST_VERSION:-1.0.6}; integrity=${TEST_LATEST_INTEGRITY:-sha512-ZGV0ZXJtaW5pc3RpYw==} ;;
  claude-spend@*) version=${2#claude-spend@}; integrity=${TEST_EXACT_INTEGRITY:-sha512-ZGV0ZXJtaW5pc3RpYw==} ;;
  *) exit 1 ;;
esac
jq -cn --arg v "$version" --arg i "$integrity" '{version:$v,"dist.integrity":$i}'
SH
cat >"$STUB_BIN/npx" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_ARGV_LOG"
SH
chmod +x "$STUB_BIN/npm" "$STUB_BIN/npx"

ALIAS=$(nix eval --raw "$ROOT#homeConfigurations.\"sungin@ct110\".config.programs.zsh.shellAliases.cspend") \
  || fail 'the Home Manager generation does not define cspend'
[ "$ALIAS" = claude-spend-pinned ] || fail 'cspend does not invoke its wrapper'
PACKAGED=$(nix eval --raw "$ROOT#homeConfigurations.\"sungin@ct110\".config.home.packages" \
  --apply 'packages: builtins.concatStringsSep " " (builtins.filter (name: name == "claude-spend-pinned") (map (package: package.name or "") packages))')
[ "$PACKAGED" = claude-spend-pinned ] || fail 'cspend wrapper is absent from Home Manager packages'

run_alias() {
  rm -f "$ARGV_LOG"
  ( export PATH="$ROOT/bin:$STUB_BIN:$PATH" TEST_ARGV_LOG="$ARGV_LOG" \
      DEV_TOOLS_NPM_BIN="$STUB_BIN/npm" DEV_TOOLS_NPX_BIN="$STUB_BIN/npx"
    eval "$ALIAS" --report )
}

run_alias
[ "$(sed -n '2p' "$ARGV_LOG")" = 'claude-spend@1.0.6' ] || fail 'cspend did not launch the resolved exact stable version'
[ "$(sed -n '3p' "$ARGV_LOG")" = --report ] || fail 'cspend lost its argument'
pass 'cspend resolves a stable version and launches the exact artifact'

export TEST_LATEST_VERSION=9.8.7
run_alias
[ "$(sed -n '2p' "$ARGV_LOG")" = 'claude-spend@9.8.7' ] || fail 'a newer stable release was not selected'
unset TEST_LATEST_VERSION
pass 'a newer stable release changes the launched version'

for mode in prerelease integrity drift; do
  case "$mode" in
    prerelease) export TEST_LATEST_VERSION=9.8.7-beta.1 ;;
    integrity) export TEST_LATEST_INTEGRITY=missing ;;
    drift) export TEST_EXACT_INTEGRITY=sha512-ZGlmZmVyZW50 ;;
  esac
  if run_alias >"$TMP_ROOT/$mode.out" 2>&1; then fail "$mode was launched"; fi
  [ ! -e "$ARGV_LOG" ] || fail "$mode still reached npx"
  unset TEST_LATEST_VERSION TEST_LATEST_INTEGRITY TEST_EXACT_INTEGRITY
done
pass 'prerelease and integrity failures never reach npx'

printf '\nall claude-spend tests passed\n'
