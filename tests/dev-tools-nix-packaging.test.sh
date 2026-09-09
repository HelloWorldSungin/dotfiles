#!/usr/bin/env bash
# Tests for the single-owner developer-tool Nix packaging in home/dev-tools.nix.
#
# Nothing here reads repository source. Every assertion comes from the real
# Home Manager generation - the derivations and generated artifacts it would
# deploy - or from executing the packaged updater out of the Nix store. No live
# tool is installed, upgraded, or restarted.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-nix-packaging-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'
BASH_BIN=$(command -v bash) || fail 'missing test dependency: bash'

CONFIG='homeConfigurations."sungin@ct110".config'

# The single interactive checker on PATH. Evaluating this also asserts the
# generation ships exactly one of them.
interactive_checker() {
  # shellcheck disable=SC2016 # the --apply argument is Nix, not shell
  nix eval --raw "$1#$CONFIG.home.packages" --apply '
    packages:
      let matches = builtins.filter (p: (p.name or "") == "dev-tools-check-updates") packages;
      in if builtins.length matches == 1 then (builtins.head matches).outPath
         else throw "expected exactly one dev-tools-check-updates package, found ${toString (builtins.length matches)}"'
}

# The generated systemd command line the weekly timer runs.
timer_command() {
  nix eval --raw "$1#$CONFIG.systemd.user.services.dev-tools-update-checker.Service.ExecStart" \
    --apply 'execStart: (builtins.head execStart).text'
}

# The generated ~/.zshrc home-manager writes, which every login shell sources.
login_shell_rc() { nix eval --raw "$1#$CONFIG.home.file.\"./.zshrc\".text"; }

# The generated guarded-updater wrapper, whose PATH export is its runtime closure.
updater_wrapper() {
  # shellcheck disable=SC2016 # the --apply argument is Nix, not shell
  nix eval --raw "$1#$CONFIG.home.packages" --apply '
    packages:
      let matches = builtins.filter (p: (p.name or "") == "dev-tools-apply-updates") packages;
      in if builtins.length matches == 1 then (builtins.head matches).text
         else throw "expected exactly one dev-tools-apply-updates package, found ${toString (builtins.length matches)}"'
}

# The set of distinct checker store paths a generated artifact resolves to.
checker_paths() { grep -oE '/nix/store/[0-9a-z]+-dev-tools-check-updates' | sort -u; }

assert_single_checker() {
  local label=$1 artifact=$2 expected=$3 found
  found=$(printf '%s' "$artifact" | checker_paths)
  [ -n "$found" ] || fail "$label does not resolve any checker derivation"
  [ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] || fail "$label resolves more than one checker derivation"
  [ "$found" = "$expected" ] || fail "$label resolves $found instead of the packaged checker $expected"
}

# ------------------------------- one checker derivation for every consumer

CHECKER=$(interactive_checker "$ROOT") || fail 'the generation does not put exactly one checker on PATH'

TIMER=$(timer_command "$ROOT")
case "$TIMER" in
  *'--force --json'*'--health --json'*) : ;;
  *) fail 'the timer command no longer runs the forced check and the health check' ;;
esac
assert_single_checker 'the weekly timer command' "$TIMER" "$CHECKER"

RC=$(login_shell_rc "$ROOT")
case "$RC" in
  *'dev-tools-check-updates --startup'*) : ;;
  *) fail 'the generated .zshrc no longer runs the startup check' ;;
esac
assert_single_checker 'the login shell startup invocation' "$RC" "$CHECKER"

UPDATER=$(updater_wrapper "$ROOT")
UPDATER_PATH_EXPORT=$(grep -m1 '^export PATH=' <<<"$UPDATER") \
  || fail 'the packaged updater declares no runtime closure'
assert_single_checker "the guarded updater's runtime closure" "$UPDATER_PATH_EXPORT" "$CHECKER"
pass 'the interactive checker, timer, login shell, and updater share one derivation'

# ------------------------------- the shared definition moves them together

# Mutating the one packaging definition must move every consumer at once. A
# second copy of the definition would leave at least one consumer behind.
SCRATCH="$TMP_ROOT/repo"
mkdir -p "$SCRATCH"
tar -C "$ROOT" --exclude=./.git -cf - . | tar -C "$SCRATCH" -xf -
# Adds one package to the checker's declared runtime closure and nothing else.
CHECKER_ONLY_INPUT='"coreutils" "curl" "gawk" "git" "gnugrep" "gnused" "jq" "nodejs_22"'
[ "$(grep -cF "$CHECKER_ONLY_INPUT" "$SCRATCH/home/dev-tools.nix")" -eq 1 ] \
  || fail 'the mutation fixture no longer targets exactly the checker closure'
python3 - "$SCRATCH/home/dev-tools.nix" "$CHECKER_ONLY_INPUT" <<'MUTATE'
import sys
path, anchor = sys.argv[1], sys.argv[2]
text = open(path).read()
open(path, 'w').write(text.replace(anchor, anchor + ' "gnutar"', 1))
MUTATE
git -C "$SCRATCH" init -q
git -C "$SCRATCH" add -A
git -C "$SCRATCH" -c user.email=tests@example.invalid -c user.name=tests commit -qm 'packaging mutation'

MUTATED_CHECKER=$(interactive_checker "$SCRATCH") \
  || fail 'the mutated generation does not put exactly one checker on PATH'
[ "$MUTATED_CHECKER" != "$CHECKER" ] || fail 'the mutation fixture did not change the checker derivation'
assert_single_checker 'the mutated weekly timer command' "$(timer_command "$SCRATCH")" "$MUTATED_CHECKER"
assert_single_checker 'the mutated login shell startup invocation' "$(login_shell_rc "$SCRATCH")" "$MUTATED_CHECKER"
MUTATED_UPDATER=$(updater_wrapper "$SCRATCH")
assert_single_checker "the mutated updater's runtime closure" \
  "$(grep -m1 '^export PATH=' <<<"$MUTATED_UPDATER")" "$MUTATED_CHECKER"
pass 'changing the shared definition moves every consumer to the same new derivation'

# ------------------------------- the packaged updater is hermetic

PACKAGED=$(nix build --no-link --print-out-paths --impure --expr "
  let config = (builtins.getFlake \"$ROOT\").$CONFIG;
  in builtins.head (builtins.filter (p: (p.name or \"\") == \"dev-tools-apply-updates\") config.home.packages)")
APPLY_BIN="$PACKAGED/bin/dev-tools-apply-updates"
[ -x "$APPLY_BIN" ] || fail 'the guarded updater did not build'

# Exact pins come from the manifest the wrapper itself bakes in, so the stubs
# below answer with the same values the packaged tool will demand.
# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$ROOT/config/dev-tools-versions.sh"
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package version integrity guarded _channel <<<"$row"
  [ "$name" = quota-axi ] || continue
  QUOTA_COMMAND=$command_name; QUOTA_VERSION=$version; QUOTA_INTEGRITY=$integrity
  [ "$guarded" = yes ] || fail 'quota-axi is no longer a guarded pin'
done
: "${QUOTA_VERSION:?quota-axi pin missing}"

SEED="$TMP_ROOT/seed"; REMOTE="$TMP_ROOT/origin.git"; CHECKOUT="$TMP_ROOT/firstmate"
mkdir -p "$SEED"
git -C "$SEED" init -q -b main
printf 'one\n' >"$SEED/version"
git -C "$SEED" add version
git -C "$SEED" -c user.email=tests@example.invalid -c user.name=tests commit -qm one
git clone -q --bare "$SEED" "$REMOTE"
git clone -q "file://$REMOTE" "$CHECKOUT"

STUBS="$TMP_ROOT/stubs"; PREFIX="$TMP_ROOT/npm-prefix"; STATE="$TMP_ROOT/state"
mkdir -p "$STUBS" "$PREFIX/bin" "$STATE" "$TMP_ROOT/home"

DETECTION=$(jq -cn --arg pin "$FIRSTMATE_REV" --arg head "$(git -C "$CHECKOUT" rev-parse HEAD)" \
  --arg quota "$QUOTA_VERSION" \
  '{schema_version:4,tools:[
      {name:"firstmate",current:$head,pinned:$pin,latest_stable:$pin,status:"drifted"},
      {name:"quota-axi",current:"0.0.1",pinned:$quota,latest_stable:$quota,status:"drifted"}
    ]}')
cat >"$STUBS/checker" <<SH
#!$BASH_BIN
printf '%s\n' '$DETECTION'
SH
cat >"$STUBS/npm" <<SH
#!$BASH_BIN
if [ "\$1" = view ]; then
  version=\${2##*@}
  if [ "\$version" = '$QUOTA_VERSION' ]; then integrity='$QUOTA_INTEGRITY'
  else integrity="sha512-prior-\$version"
  fi
  printf '{"version":"%s","dist.integrity":"%s"}\n' "\$version" "\$integrity"
  exit 0
fi
if [ "\$1" = install ]; then
  mkdir -p "\$NPM_CONFIG_PREFIX/bin"
  printf '#!$BASH_BIN\nprintf "%s %s\\\\n"\n' '$QUOTA_COMMAND' '$QUOTA_VERSION' >"\$NPM_CONFIG_PREFIX/bin/$QUOTA_COMMAND"
  chmod +x "\$NPM_CONFIG_PREFIX/bin/$QUOTA_COMMAND"
  exit 0
fi
exit 1
SH
chmod +x "$STUBS/checker" "$STUBS/npm"

# `env -i PATH=/nonexistent` leaves the packaged wrapper nothing but its own
# declared closure: awk parses `git ls-remote`, grep validates the commit,
# version, and integrity pins, and sed prints the operator contract.
run_stripped() {
  env -i PATH=/nonexistent HOME="$TMP_ROOT/home" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$STUBS/checker" \
    DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" \
    DEV_TOOLS_FIRSTMATE_REPO="file://$REMOTE" \
    DEV_TOOLS_UPDATE_NPM_BIN="$STUBS/npm" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" \
    "$APPLY_BIN" "$@"
}

set +e
json=$(run_stripped --json)
set -e
[ -n "$json" ] || fail 'the packaged updater produced no result from its own closure'
firstmate_status=$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')
firstmate_detail=$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')
[ "$firstmate_detail" != 'unsafe Firstmate commit pin' ] \
  || fail 'a stripped PATH made the packaged updater reject its own well-formed commit pin'
# awk is the only thing that turns `git ls-remote` output into the remote head;
# without it the run stops one step earlier, at a different refusal.
[ "$firstmate_detail" = 'the exact pin is absent from the authoritative Firstmate main branch' ] \
  || fail "the packaged updater did not re-verify the authoritative remote: $firstmate_status - $firstmate_detail"
quota_status=$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')
quota_detail=$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')
[ "$quota_detail" != 'unsafe exact version or integrity pin' ] \
  || fail 'a stripped PATH made the packaged updater reject its own exact npm pins'
[ "$quota_status" = applied ] || fail "the packaged updater did not converge its exact npm pin: $quota_status - $quota_detail"
[ "$("$PREFIX/bin/$QUOTA_COMMAND" | awk '{print $2}')" = "$QUOTA_VERSION" ] \
  || fail 'the packaged updater did not install the exact pinned version'

help=$(run_stripped --help)
case "$help" in
  *'MUST NEVER install, update, invoke, reload, stop, or restart'*) : ;;
  *) fail 'a stripped PATH left the packaged --help unable to print the operator contract' ;;
esac
pass 'the packaged updater runs entirely from its declared closure'

# ------------------------- every wrapper runtime input is in the pin inventory

# config/dev-tools-versions.sh states that its Nix rows cover the runtime inputs
# of the repository-owned wrappers, so the deployed closure and the manifest have
# to agree. The comparison is by store path, not by name: an attribute whose
# store name differs from it (nodejs_22 -> nodejs-22.23.2) would otherwise look
# like a miss. Scope is the four wrappers on PATH.
# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$ROOT/config/dev-tools-versions.sh"
pinned_attrs=()
closure_attrs=()
user_env_attrs=()
for row in "${NIX_PACKAGE_PINS[@]}"; do
  IFS='|' read -r attr _command _version evidence <<<"$row"
  pinned_attrs+=("$attr")
  case "$evidence" in
    closure) closure_attrs+=("$attr") ;;
    user-env) user_env_attrs+=("$attr") ;;
    *) fail "the pin row for $attr carries no evidence class" ;;
  esac
done
[ "${#pinned_attrs[@]}" -gt 0 ] || fail 'the pin manifest declares no Nix packages'
[ "${#closure_attrs[@]}" -gt 0 ] || fail 'the pin manifest classes no package as closure-only'
[ "${#user_env_attrs[@]}" -gt 0 ] || fail 'the pin manifest classes no package as user-env'

PINNED_ROWS=$(nix eval --raw "$ROOT#homeConfigurations.\"sungin@ct110\".pkgs" --apply \
  "pkgs: builtins.concatStringsSep \"\n\" (map (n: n + \" \" + (builtins.getAttr n pkgs).outPath) [ $(printf '"%s" ' "${pinned_attrs[@]}")])") \
  || fail 'the pin manifest names a Nix package the pinned nixpkgs does not have'
PINNED_PATHS=$(awk '{print $2}' <<<"$PINNED_ROWS")
pinned_path_of() { awk -v n="$1" '$1 == n {print $2}' <<<"$PINNED_ROWS"; }

wrapper_text() { # wrapper name -> its generated script
  # shellcheck disable=SC2016 # the --apply argument is Nix, not shell
  nix eval --raw "$ROOT#$CONFIG.home.packages" --apply "
    packages:
      let matches = builtins.filter (p: (p.name or \"\") == \"$1\") packages;
      in if builtins.length matches == 1 then (builtins.head matches).text
         else throw \"expected exactly one $1 package\""
}

for wrapper in dev-tools-check-updates dev-tools-install-pinned claude-spend-pinned dev-tools-apply-updates; do
  text=$(wrapper_text "$wrapper") || fail "the generation does not ship exactly one $wrapper"
  path_line=$(grep -m1 '^export PATH=' <<<"$text") || fail "$wrapper declares no runtime closure"
  path_line=${path_line#export PATH=\"}
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in /nix/store/*) : ;; *) continue ;; esac
    store_path=${entry%/bin}
    # A wrapper may depend on a sibling wrapper; those are not nixpkgs packages.
    case "$store_path" in
      *-dev-tools-check-updates|*-dev-tools-versions.sh) continue ;;
    esac
    printf '%s\n' "$PINNED_PATHS" | grep -Fqx "$store_path" \
      || fail "$wrapper depends on ${store_path##*/} but no NIX_PACKAGE_PINS row names it"
  done <<<"$(printf '%s' "$path_line" | tr ':' '\n')"
done
pass 'every runtime input of every packaged wrapper has a pin inventory row'

# ------------------------- the generated closure manifest is the measurement

# home/dev-tools.nix owns one closure-input attrset; the manifest it generates is
# what the checker measures closure-only packages with, so it has to name exactly
# those packages at exactly the store paths the wrappers carry.
# Reached the way the checker reaches it: the path its own wrapper exports. The
# manifest is a generated artifact with an owned schema, so reading it back is
# reading the contract the checker consumes.
BUILT_CHECKER=$(nix build --no-link --print-out-paths --impure --expr "
  let config = (builtins.getFlake \"$ROOT\").$CONFIG;
  in builtins.head (builtins.filter (p: (p.name or \"\") == \"dev-tools-check-updates\") config.home.packages)") \
  || fail 'the packaged checker did not build'
MANIFEST_PATH=$(grep -m1 '^export DEV_TOOLS_CLOSURE_FILE=' "$BUILT_CHECKER/bin/dev-tools-check-updates" | cut -d= -f2) \
  || fail 'the packaged checker does not export a closure measurement manifest'
[ -r "$MANIFEST_PATH" ] || fail "the exported closure manifest is not readable: $MANIFEST_PATH"
MANIFEST=$(cat "$MANIFEST_PATH")
printf '%s' "$MANIFEST" | jq -e 'type == "array" and length > 0' >/dev/null \
  || fail 'the closure manifest is not a non-empty array'
while IFS= read -r manifest_name; do
  [ -n "$manifest_name" ] || continue
  manifest_path=$(printf '%s' "$MANIFEST" | jq -r --arg n "$manifest_name" '.[] | select(.name == $n) | .store_path')
  evaluated=$(pinned_path_of "$manifest_name")
  [ -n "$evaluated" ] \
    || fail "the closure manifest names $manifest_name but no NIX_PACKAGE_PINS row does"
  [ "$manifest_path" = "$evaluated" ] \
    || fail "the closure manifest points $manifest_name at $manifest_path instead of $evaluated"
  printf '%s\n' "${closure_attrs[@]}" | grep -Fqx "$manifest_name" \
    || fail "the closure manifest measures $manifest_name, which its pin row does not class as closure-only"
done <<<"$(printf '%s' "$MANIFEST" | jq -r '.[].name')"
for attr in "${closure_attrs[@]}"; do
  printf '%s' "$MANIFEST" | jq -e --arg n "$attr" 'any(.[]; .name == $n)' >/dev/null \
    || fail "$attr is classed closure-only but the generated manifest cannot measure it"
done

# The other half of the split has to be earned: a row keeps its ambient
# measurement only when the package really is in the user environment, so the
# command the operator runs is the pinned one. Checked for the wrapper inputs,
# which are the packages the split decides about.
HOME_PATHS=$(nix eval --raw "$ROOT#$CONFIG.home.packages" \
  --apply 'ps: builtins.concatStringsSep "\n" (map (p: p.outPath) ps)') \
  || fail 'the generation exposes no home.packages closure'
for attr in "${closure_attrs[@]}"; do
  if printf '%s\n' "$HOME_PATHS" | grep -Fqx "$(pinned_path_of "$attr")"; then
    fail "$attr is in the user environment, so classing it closure-only hides drift the operator would see"
  fi
done

# Nothing a wrapper carries may be unmeasurable: each input is either in the
# manifest, or user-facing and therefore honestly measured through PATH.
for wrapper in dev-tools-check-updates dev-tools-install-pinned claude-spend-pinned dev-tools-apply-updates; do
  text=$(wrapper_text "$wrapper") || fail "the generation does not ship exactly one $wrapper"
  path_line=$(grep -m1 '^export PATH=' <<<"$text") || fail "$wrapper declares no runtime closure"
  while IFS= read -r entry; do
    case "$entry" in /nix/store/*) : ;; *) continue ;; esac
    store_path=${entry%/bin}
    case "$store_path" in *-dev-tools-check-updates|*-dev-tools-versions.sh) continue ;; esac
    printf '%s' "$MANIFEST" | jq -e --arg p "$store_path" 'any(.[]; .store_path == $p)' >/dev/null && continue
    attr=$(awk -v p="$store_path" '$2 == p {print $1}' <<<"$PINNED_ROWS")
    printf '%s\n' "${user_env_attrs[@]}" | grep -Fqx "$attr" \
      || fail "$wrapper carries ${store_path##*/}, which is neither in the closure manifest nor classed user-env"
    printf '%s\n' "$HOME_PATHS" | grep -Fqx "$store_path" \
      || fail "$wrapper carries ${store_path##*/} as a user-env row, but it is not in the user environment"
  done <<<"$(printf '%s' "${path_line#export PATH=\"}" | tr ':' '\n')"
done
pass 'the closure manifest measures exactly the closure-only rows, and every other wrapper input is user-facing'

printf '\nall dev-tools nix packaging tests passed\n'
