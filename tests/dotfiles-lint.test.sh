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
# The same shape but clean, and using bash-only syntax. ShellCheck reports
# SC2148 on any shebangless file it is not told a shell for, so this file is
# silent only if the entry point supplied one.
cat >"$REPO/lib/clean.sh" <<'SH'
choices=(one two)
greet() {
  echo "${choices[0]}$1"
}
SH
# A *.sh whose shebang names a shell ShellCheck refuses (SC1071): the shebang
# has to win over the name, or the gate hard-fails on an unparseable file.
cat >"$REPO/lib/zshlib.sh" <<'SH'
#!/usr/bin/env zsh
print -r -- hi
SH
# An extensionless shell script outside bin/, the shape of
# system/ct110-network-failover/vpn-ethernet-failover, with its own SC2086.
cat >"$REPO/system/runner" <<'SH'
#!/usr/bin/env bash
run() {
  echo $2
}
SH
# Extensionless and declaring nothing: not a shell file.
echo 'plain data, no shebang' >"$REPO/system/datafile"
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

# The entry point reports how many files it selected before handing them over.
checked=$(awk '/^dotfiles-lint: checking [0-9]+ shell file\(s\)$/ { print $3 }' "$OUT")

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

if grep -qF 'SC2148' "$OUT"; then
  report 'a shebangless *.sh file was linted without being told a shell'
fi
# bin/dotfiles-lint, system/runner, lib/helpers.sh and lib/clean.sh. Pinning the
# count is what proves lib/clean.sh reached ShellCheck at all, and its silence
# is what proves the shell it was given was bash: its array syntax is reported
# under any other dialect.
if [ "$checked" != 4 ]; then
  report "expected 4 selected files, the entry point reported ${checked:-none}"
fi
if analyzed_has 'lib/clean.sh'; then
  report 'a clean bash sourced library was reported on, so it was not linted as bash'
fi
pass 'a shebangless *.sh file is selected and linted as bash, so a clean bash library stays silent'

if analyzed_has 'lib/zshlib.sh'; then
  report 'a *.sh declaring an unsupported shell was handed to ShellCheck'
fi
if grep -qF 'SC1071' "$OUT"; then
  report 'ShellCheck was asked to parse a shell it does not support'
fi
if ! grep -qF 'lib/zshlib.sh (#!zsh)' "$OUT"; then
  report 'a *.sh declaring an unsupported shell was not reported as skipped, or not by its shell'
fi
pass 'a *.sh whose shebang names an unsupported shell is skipped, named, and not parsed'

if ! analyzed_has 'system/runner'; then
  report 'an extensionless shell script outside bin/ was not analyzed'
fi
pass 'an extensionless file with a supported shell shebang is analyzed'

if analyzed_has 'bin/tool.js'; then
  report 'a non-shell script was analyzed'
fi
if ! skipped_has 'bin/tool.js'; then
  report 'a non-shell script was excluded without being reported'
fi
pass 'a non-shell script is excluded and the exclusion is reported'

for quiet in system/datafile notes.md; do
  if grep -qF "$quiet" "$OUT"; then
    report "a file declaring no shell and not named *.sh was reported: $quiet"
  fi
done
pass 'files declaring no shell and not named *.sh are neither analyzed nor named'

printf 'dotfiles-lint tests passed\n'
