#!/usr/bin/env bash
# Behavioral tests for bin/dotfiles-lint's file selection.
#
# The entry point resolves its root from its own location, so it is run for
# real from a copy inside a throwaway git repository whose tracked files are
# planted with known ShellCheck defects. Which files it actually analyzed is
# then read back out of ShellCheck's own report, not out of the selection code.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENTRY="$ROOT/bin/dotfiles-lint"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lint-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v shellcheck >/dev/null 2>&1 || fail 'missing test dependency: shellcheck'
GIT_BIN=$(command -v git) || fail 'missing test dependency: git'
[ -x "$ENTRY" ] || fail 'bin/dotfiles-lint is missing or not executable'

REPO="$TMP_ROOT/repo"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/system"
cp -p "$ENTRY" "$REPO/bin/dotfiles-lint"

# A sourced shell library: *.sh, deliberately no shebang. The unquoted
# expansion is SC2086, so analyzing this file is what makes it fail.
cat >"$REPO/lib/helpers.sh" <<'SH'
greet() {
  echo $1
}
SH
# An extensionless shell script outside bin/, the shape of
# system/ct110-network-failover/vpn-ethernet-failover, with its own SC2086.
cat >"$REPO/system/runner" <<'SH'
#!/usr/bin/env bash
run() {
  echo $2
}
SH
# Not a shell script: a shell-looking name is not what decides this.
cat >"$REPO/bin/tool.js" <<'JS'
#!/usr/bin/env node
console.log(1)
JS
echo 'notes, not a script' >"$REPO/notes.md"

$GIT_BIN -C "$REPO" init -q -b main .
$GIT_BIN -C "$REPO" add -A

OUT="$TMP_ROOT/lint.out"
status=0
(cd "$REPO" && bin/dotfiles-lint) >"$OUT" 2>&1 || status=$?

# ShellCheck's tty report names each file it had a finding in; that report is
# the entry point's own output, so the set of names in it is the set of files
# that were really analyzed.
analyzed=$(awk '/^In .+ line [0-9]+:$/ { print $2 }' "$OUT" | sort -u)
# The skipped list is the indented block under the entry point's own header,
# which ends at the blank line ShellCheck's report opens with.
skipped=$(awk '
  /^dotfiles-lint: .*skipped [0-9]+ file\(s\):$/ { inlist = 1; next }
  inlist && /^  [^ ]/ { print $1; next }
  inlist { exit }
' "$OUT" | sort -u)

analyzed_has() { grep -qxF "$1" <<<"$analyzed"; }
skipped_has() { grep -qxF "$1" <<<"$skipped"; }
report() { cat "$OUT" >&2; fail "$1"; }

if [ "$status" -eq 0 ]; then
  report 'planted ShellCheck defects did not fail bin/dotfiles-lint'
fi
pass 'planted ShellCheck defects fail bin/dotfiles-lint'

# The regression: a *.sh file with no shebang is a shell file and must be
# analyzed, not skipped.
if ! analyzed_has 'lib/helpers.sh'; then
  report 'a shebangless tracked *.sh file was not analyzed'
fi
pass 'a shebangless tracked *.sh file is analyzed'

if grep -qE '\.sh$' <<<"$skipped"; then
  report 'a tracked *.sh file was reported as not a shell script'
fi
pass 'no tracked *.sh file is reported as not a shell script'

if ! analyzed_has 'system/runner'; then
  report 'an extensionless shell script outside bin/ was not analyzed'
fi
pass 'an extensionless shell script outside bin/ is analyzed'

if analyzed_has 'bin/tool.js'; then
  report 'a non-shell script was analyzed'
fi
if ! skipped_has 'bin/tool.js'; then
  report 'a non-shell script was excluded without being reported'
fi
pass 'a non-shell script is excluded and the exclusion is reported'

if grep -qF 'notes.md' "$OUT"; then
  report 'a file with neither a shell name nor a shebang was reported'
fi
pass 'a file with neither a shell name nor a shebang is not reported at all'

printf 'dotfiles-lint tests passed\n'
