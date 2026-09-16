#!/usr/bin/env bash
# shellcheck disable=SC2016 # quoted snippets are passed into zsh, not expanded here
# Behavior tests for CT110's unset-only FM_HOME default in the Home Manager
# generated zshenv. Assertions run against the generation text and against
# isolated zsh login/interactive children. No live ~/.zshrc is edited, and no
# real Firstmate supervisor, session lock, or model call is started.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-home-default-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'
ZSH_BIN=$(command -v zsh) || fail 'missing test dependency: zsh'

DEFAULT_HOME=/home/sungin/firstmate-upstream
CONFIG='homeConfigurations."sungin@ct110".config'

zshenv_text() {
  nix eval --raw "$1#$CONFIG.home.file.\"./.zshenv\".text"
}

session_vars_text() {
  nix eval --raw "$1#$CONFIG.home.sessionVariables.EDITOR"
}

ZSHENV=$(zshenv_text "$ROOT") || fail 'could not evaluate the generated CT110 .zshenv'
printf '%s\n' "$ZSHENV" | grep -Fq 'export FM_HOME=/home/sungin/firstmate-upstream' \
  || fail 'the generated .zshenv does not export the established Firstmate home'
printf '%s\n' "$ZSHENV" | grep -Fq '[ -z "${FM_HOME+x}" ]' \
  || fail 'the generated .zshenv does not default FM_HOME only when unset'
printf '%s\n' "$ZSHENV" | grep -E 'sessionVariables|FM_HOME=.*firstmate-upstream' >/dev/null
case "$ZSHENV" in
  *'export FM_HOME=/home/sungin/firstmate-upstream'*) : ;;
  *) fail 'expected an unset-only export of the established home' ;;
esac
# An unconditional assignment would clobber explicit empty and overrides.
unconditional=$(printf '%s\n' "$ZSHENV" | grep -c 'export FM_HOME=/home/sungin/firstmate-upstream' || true)
[ "$unconditional" -eq 1 ] || fail 'FM_HOME default must appear once'
pass 'generated CT110 .zshenv defaults FM_HOME only when unset'

SESSION_JSON=$(nix eval --json "$ROOT#$CONFIG.home.sessionVariables")
printf '%s' "$SESSION_JSON" | grep -F '"FM_HOME"' >/dev/null \
  && fail "home.sessionVariables must not own FM_HOME (got $SESSION_JSON)"
EDITOR_VAL=$(session_vars_text "$ROOT")
[ "$EDITOR_VAL" = nvim ] || fail "unrelated session default EDITOR changed (got $EDITOR_VAL)"
pass 'other Home Manager session defaults stay off FM_HOME'

grep -F 'FM_HOME' "$ROOT/home/sungin-mac.nix" >/dev/null \
  && fail 'the Mac Home Manager module must not carry the CT110 FM_HOME default'
pass 'Mac module does not default FM_HOME'

ZDOT="$TMP_ROOT/zdot"
mkdir -p "$ZDOT" "$TMP_ROOT/home" "$TMP_ROOT/bin"
# Isolate ZDOTDIR so login/interactive zsh load only the generation fragment
# under test, never the live managed ~/.zshrc.
printf '%s\n' "$ZSHENV" >"$ZDOT/.zshenv"
cat >"$ZDOT/.zshrc" <<'ZSHRC'
# interactive-only marker; FM_HOME must already be decided in .zshenv
:
ZSHRC

run_zsh() { # run_zsh <label-env...> -- <zsh-args...>
  local -a prefix=()
  while [ $# -gt 0 ]; do
    case $1 in
      --) shift; break ;;
      *) prefix+=("$1"); shift ;;
    esac
  done
  env "${prefix[@]}" \
    HOME="$TMP_ROOT/home" \
    ZDOTDIR="$ZDOT" \
    "$ZSH_BIN" "$@"
}

got=$(run_zsh -u FM_HOME -- -lc 'printf %s "$FM_HOME"')
[ "$got" = "$DEFAULT_HOME" ] || fail "login shell did not default FM_HOME (got '$got')"
pass 'fresh login shell defaults FM_HOME when unset'

got=$(run_zsh -u FM_HOME -- -ic 'printf %s "$FM_HOME"')
[ "$got" = "$DEFAULT_HOME" ] || fail "interactive shell did not default FM_HOME (got '$got')"
pass 'interactive shell defaults FM_HOME when unset'

got=$(run_zsh -u FM_HOME -- -lc 'zsh -c "printf %s \"\$FM_HOME\""')
[ "$got" = "$DEFAULT_HOME" ] || fail "child shell lost the exported default (got '$got')"
pass 'child shells inherit the exported default'

got=$(run_zsh FM_HOME= -- -lc 'printf %s "${FM_HOME+set}:${#FM_HOME}"')
[ "$got" = 'set:0' ] || fail "explicit empty FM_HOME was not preserved (got '$got')"
pass 'explicit empty FM_HOME is preserved'

PRIMARY_OVERRIDE=/home/sungin/firstmate-upstream
got=$(run_zsh FM_HOME="$PRIMARY_OVERRIDE" -- -lc 'printf %s "$FM_HOME"')
[ "$got" = "$PRIMARY_OVERRIDE" ] || fail "explicit primary FM_HOME was rewritten (got '$got')"
pass 'explicit primary FM_HOME is preserved'

SECOND_OVERRIDE="$TMP_ROOT/secondmate-home"
mkdir -p "$SECOND_OVERRIDE"
got=$(run_zsh FM_HOME="$SECOND_OVERRIDE" -- -lc 'printf %s "$FM_HOME"')
[ "$got" = "$SECOND_OVERRIDE" ] || fail "explicit secondmate FM_HOME was rewritten (got '$got')"
pass 'explicit secondmate FM_HOME is preserved'

# Supported Firstmate launch is `pi` from the checkout (README install/launch).
# Stub pi, claude, grok, and omp so a mistaken PATH still cannot start a
# supervisor, take a session lock, or call a model.
cat >"$TMP_ROOT/bin/pi" <<'STUB'
#!/usr/bin/env bash
printf 'stub-pi FM_HOME=%s cwd=%s args=%s\n' "${FM_HOME-<unset>}" "$PWD" "$*"
exit 0
STUB
chmod 0755 "$TMP_ROOT/bin/pi"
for blocked in claude grok omp pi-signed fm-session-start.sh; do
  cat >"$TMP_ROOT/bin/$blocked" <<STUB
#!/usr/bin/env bash
printf 'blocked real %s invocation\n' '$blocked' >&2
exit 97
STUB
  chmod 0755 "$TMP_ROOT/bin/$blocked"
done

FAKE_CHECKOUT="$TMP_ROOT/firstmate-upstream"
mkdir -p "$FAKE_CHECKOUT"
printf '%s\n' 'stub checkout' >"$FAKE_CHECKOUT/README.md"

launch_out=$(
  run_zsh -u FM_HOME PATH="$TMP_ROOT/bin:/usr/bin:/bin" -- -lc \
    "cd $(printf %q "$FAKE_CHECKOUT") && command -v pi >/dev/null && pi"
)
printf '%s\n' "$launch_out" | grep -Fq "stub-pi FM_HOME=$DEFAULT_HOME" \
  || fail "supported pi launch did not see the default FM_HOME: $launch_out"
printf '%s\n' "$launch_out" | grep -Fq "cwd=$FAKE_CHECKOUT" \
  || fail "supported pi launch did not run from the checkout: $launch_out"
pass 'supported Firstmate pi launch sees the default home through isolated stubs'
