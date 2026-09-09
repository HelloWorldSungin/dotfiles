#!/usr/bin/env bash
# Behavior tests for the mutation receipt and the attended rollback contract.
#
# Everything runs against stubs in a temp tree: a stub checker, a stub npm whose
# registry answers come from files the test controls, and a transparent git
# wrapper that only records whether the receipt already existed when a mutation
# started. No live tool, package, or service is ever touched. The receipt is a
# persisted, operator-facing record with an owned schema, so reading it back is
# reading this tool's own output contract.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLY="$ROOT/bin/dev-tools-apply-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-apply-rollback-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

BASH_BIN=$(command -v bash) || fail 'missing test dependency: bash'
REAL_GIT=$(command -v git) || fail 'missing test dependency: git'
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# ------------------------------------------------------------------ fixtures

SEED="$TMP_ROOT/seed"; REMOTE="$TMP_ROOT/origin.git"; CHECKOUT="$TMP_ROOT/firstmate"
mkdir -p "$SEED"
git -C "$SEED" init -q -b main
printf 'one\n' >"$SEED/version"
git -C "$SEED" add version
git -C "$SEED" -c user.email=tests@example.invalid -c user.name=tests commit -qm one
git clone -q --bare "$SEED" "$REMOTE"
git clone -q "file://$REMOTE" "$CHECKOUT"
PRIOR_COMMIT=$(git -C "$CHECKOUT" rev-parse HEAD)
printf 'two\n' >>"$SEED/version"
git -C "$SEED" -c user.email=tests@example.invalid -c user.name=tests commit -qam two
TARGET_COMMIT=$(git -C "$SEED" rev-parse HEAD)
git -C "$SEED" push -q "file://$REMOTE" main

PINS="$TMP_ROOT/pins.sh"
cp "$ROOT/config/dev-tools-versions.sh" "$PINS"
printf '\nFIRSTMATE_REV=%s\n' "$TARGET_COMMIT" >>"$PINS"
# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS"
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package version integrity guarded _channel <<<"$row"
  [ "$guarded" = yes ] || continue
  case "$name" in
    quota-axi) QUOTA_COMMAND=$command_name; QUOTA_VERSION=$version; QUOTA_INTEGRITY=$integrity ;;
    gh-axi) GH_COMMAND=$command_name; GH_VERSION=$version ;;
  esac
done
: "${QUOTA_VERSION:?quota-axi pin missing}"
: "${GH_VERSION:?gh-axi pin missing}"
QUOTA_PRIOR=1.2.3
GH_PRIOR=2.3.4
QUOTA_PRIOR_INTEGRITY=sha512-QUOTAAXIPRIORREGISTRYINTEGRITYEVIDENCE00000000000000000000000000000000000000000000000000==
GH_PRIOR_INTEGRITY=sha512-GHAXIPRIORREGISTRYINTEGRITYEVIDENCE0000000000000000000000000000000000000000000000000000==

FAKEBIN="$TMP_ROOT/fakebin"; PREFIX="$TMP_ROOT/npm-prefix"; STATE="$TMP_ROOT/state"
RECEIPTS="$TMP_ROOT/receipts"; REGISTRY="$TMP_ROOT/registry"
mkdir -p "$FAKEBIN" "$PREFIX/bin" "$STATE" "$RECEIPTS" "$REGISTRY" "$TMP_ROOT/home"
NPM_LOG="$TMP_ROOT/npm.log"; PRE_LOG="$TMP_ROOT/pre-mutation.log"; LIFECYCLE_LOG="$TMP_ROOT/lifecycle.log"
: >"$NPM_LOG"; : >"$PRE_LOG"; : >"$LIFECYCLE_LOG"

# The stub registry: one file per publishable package@version holding its integrity.
publish() { printf '%s' "$2" >"$REGISTRY/$1"; }
unpublish() { rm -f "$REGISTRY/$1"; }
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
publish "gh-axi@$GH_PRIOR" "$GH_PRIOR_INTEGRITY"

fake_install() { # command, version
  printf '#!%s\nprintf "%s %s\\n"\n' "$BASH_BIN" "$1" "$2" >"$PREFIX/bin/$1"
  chmod +x "$PREFIX/bin/$1"
}
fake_install "$QUOTA_COMMAND" "$QUOTA_PRIOR"
fake_install "$GH_COMMAND" "$GH_PRIOR"

cat >"$FAKEBIN/checker" <<SH
#!$BASH_BIN
set -eu
# shellcheck source=/dev/null
source "\$TEST_PINS"
head=\$($REAL_GIT -C "\$TEST_FIRSTMATE" rev-parse HEAD)
tools=\$(jq -cn --arg current "\$head" --arg pin "\$FIRSTMATE_REV" \\
  '[{name:"firstmate",current:\$current,pinned:\$pin,latest_stable:\$pin,status:(if \$current==\$pin then "up_to_date" else "drifted" end)}]')
for row in "\${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package pinned _integrity guarded _channel <<<"\$row"
  [ "\$guarded" = yes ] || continue
  current=\$pinned
  if [ -x "\$TEST_PREFIX/bin/\$command_name" ]; then
    current=\$(env NO_UPDATE_NOTIFIER=1 "\$TEST_PREFIX/bin/\$command_name" --version 2>/dev/null | grep -Eo '[0-9]+(\\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?' | head -1)
  fi
  [ "\$name" = quota-axi ] && [ -n "\${TEST_QUOTA_CURRENT:-}" ] && current=\$TEST_QUOTA_CURRENT
  item=\$(jq -cn --arg n "\$name" --arg c "\$current" --arg p "\$pinned" \\
    '{name:\$n,current:\$c,pinned:\$p,latest_stable:\$p,status:(if \$c==\$p then "up_to_date" else "drifted" end)}')
  tools=\$(jq -cn --argjson t "\$tools" --argjson i "\$item" '\$t+[\$i]')
done
jq -cn --argjson tools "\$tools" '{schema_version:4,tools:\$tools}'
SH

cat >"$FAKEBIN/npm" <<SH
#!$BASH_BIN
set -eu
printf '%s\n' "\$*" >>"\$TEST_NPM_LOG"
# shellcheck source=/dev/null
source "\$TEST_PINS"
if [ "\$1" = view ]; then
  spec=\$2
  package=\${spec%@*}
  version=\${spec##*@}
  for row in "\${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r _name _command_name candidate pinned integrity guarded _channel <<<"\$row"
    [ "\$guarded" = yes ] || continue
    [ "\$candidate" = "\$package" ] || continue
    if [ "\$version" = "\$pinned" ]; then
      jq -cn --arg v "\$version" --arg i "\$integrity" '{version:\$v,"dist.integrity":\$i}'
      exit 0
    fi
  done
  if [ -f "\$TEST_REGISTRY/\$package@\$version" ]; then
    jq -cn --arg v "\$version" --arg i "\$(cat "\$TEST_REGISTRY/\$package@\$version")" '{version:\$v,"dist.integrity":\$i}'
    # Retires the version after this answer, so the tier preflight sees it and
    # the per-tool re-verification that follows does not.
    if [ "\${TEST_RETIRE_AFTER_VIEW:-}" = "\$package@\$version" ]; then
      rm -f "\$TEST_REGISTRY/\$package@\$version"
    fi
    exit 0
  fi
  exit 1
fi
if [ "\$1" = install ]; then
  if ls "\$TEST_RECEIPT_DIR"/apply-*.json >/dev/null 2>&1; then printf 'npm-install receipt=yes\n' >>"\$TEST_PRE_LOG"
  else printf 'npm-install receipt=no\n' >>"\$TEST_PRE_LOG"; fi
  spec=\$3
  if [ -f "\$spec" ]; then
    base=\${spec##*/}; base=\${base%.tgz}
    version=\${base##*-}
    package=\${base%-*}
  else
    package=\${spec%@*}
    version=\${spec##*@}
  fi
  for row in "\${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r _name command_name candidate pinned _integrity guarded _channel <<<"\$row"
    [ "\$guarded" = yes ] || continue
    [ "\$candidate" = "\$package" ] || continue
    reported=\$version
    [ "\${TEST_BAD_INSTALL:-0}" = 1 ] && [ "\$version" = "\$pinned" ] && reported=0.0.0
    mkdir -p "\$NPM_CONFIG_PREFIX/bin"
    printf '#!$BASH_BIN\nprintf "%s %s\\\\n"\n' "\$command_name" "\$reported" >"\$NPM_CONFIG_PREFIX/bin/\$command_name"
    chmod +x "\$NPM_CONFIG_PREFIX/bin/\$command_name"
    # The install succeeded; now make the receipt unwritable so the settle that
    # follows this real mutation fails the way a full filesystem would.
    if [ "\${TEST_BREAK_RECEIPT:-}" = "\$package" ]; then rm -rf "\$TEST_RECEIPT_DIR"; : >"\$TEST_RECEIPT_DIR"; fi
    exit 0
  done
fi
exit 1
SH

# Transparent: it only observes whether the receipt already exists when a
# mutation starts, then hands every argument to the real git.
cat >"$FAKEBIN/git" <<SH
#!$BASH_BIN
for arg in "\$@"; do
  if [ "\$arg" = merge ] || [ "\$arg" = reset ]; then
    if ls "\$TEST_RECEIPT_DIR"/apply-*.json >/dev/null 2>&1; then printf 'git-%s receipt=yes\n' "\$arg" >>"\$TEST_PRE_LOG"
    else printf 'git-%s receipt=no\n' "\$arg" >>"\$TEST_PRE_LOG"; fi
    break
  fi
done
# The rollback observes the checkout after it has already read the receipt, so
# this is the moment to make the receipt's own directory unusable. A regular
# file where a directory belongs defeats mktemp for every uid, unlike a chmod.
if [ -n "\${TEST_BREAK_RECEIPT_DIR:-}" ]; then
  case "\$*" in
    *rev-parse*) rm -rf "\$TEST_BREAK_RECEIPT_DIR"; : >"\$TEST_BREAK_RECEIPT_DIR" ;;
  esac
fi
exec $REAL_GIT "\$@"
SH

cat >"$FAKEBIN/herdr" <<SH
#!$BASH_BIN
printf 'herdr %s\n' "\$*" >>"\$TEST_LIFECYCLE_LOG"
exit 99
SH
cat >"$FAKEBIN/no-mistakes" <<SH
#!$BASH_BIN
printf 'no-mistakes %s\n' "\$*" >>"\$TEST_LIFECYCLE_LOG"
exit 99
SH
chmod +x "$FAKEBIN"/*

run_tool() {
  env HOME="$TMP_ROOT/home" PATH="$FAKEBIN:/usr/bin:/bin" DEV_TOOLS_PINS_FILE="$PINS" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$FAKEBIN/checker" DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" \
    DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" DEV_TOOLS_FIRSTMATE_REPO="file://$REMOTE" \
    DEV_TOOLS_UPDATE_NPM_BIN="$FAKEBIN/npm" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" \
    DEV_TOOLS_UPDATE_GIT_BIN="$FAKEBIN/git" \
    DEV_TOOLS_APPLY_RECEIPT_DIR="${TEST_RECEIPT_DIR:-$RECEIPTS}" \
    TEST_PINS="$PINS" TEST_PREFIX="$PREFIX" TEST_FIRSTMATE="$CHECKOUT" TEST_NPM_LOG="$NPM_LOG" \
    TEST_PRE_LOG="$PRE_LOG" TEST_LIFECYCLE_LOG="$LIFECYCLE_LOG" TEST_REGISTRY="$REGISTRY" \
    TEST_BREAK_RECEIPT_DIR="${TEST_BREAK_RECEIPT_DIR:-}" \
    TEST_QUOTA_CURRENT="${TEST_QUOTA_CURRENT:-}" \
    TEST_RETIRE_AFTER_VIEW="${TEST_RETIRE_AFTER_VIEW:-}" \
    DEV_TOOLS_APPLY_PRIOR_ARTIFACT_DIR="${TEST_ARTIFACT_DIR:-}" \
    TEST_RECEIPT_DIR="${TEST_RECEIPT_DIR:-$RECEIPTS}" TEST_BAD_INSTALL="${TEST_BAD_INSTALL:-0}" \
    TEST_BREAK_RECEIPT="${TEST_BREAK_RECEIPT:-}" \
    "$APPLY" "$@"
}
run_rollback() { run_tool --rollback "$1" "${@:2}"; }

work_receipt() { cp "$RECEIPT" "$RECEIPTS/work-$1.json"; printf '%s\n' "$RECEIPTS/work-$1.json"; }
head_commit() { git -C "$CHECKOUT" rev-parse HEAD; }
tool_version() { env NO_UPDATE_NOTIFIER=1 "$PREFIX/bin/$1" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){2,3}' | head -1; }
tool_status() { printf '%s' "$1" | jq -r --arg n "$2" '.tools[] | select(.name==$n) | .status'; }
tool_detail() { printf '%s' "$1" | jq -r --arg n "$2" '.tools[] | select(.name==$n) | .detail'; }
package_status() { printf '%s' "$1" | jq -r --arg n "$2" '.tiers.npm_global.packages[] | select(.name==$n) | .status'; }
package_detail() { printf '%s' "$1" | jq -r --arg n "$2" '.tiers.npm_global.packages[] | select(.name==$n) | .detail'; }
converged() { [ "$(head_commit)" = "$TARGET_COMMIT" ] && [ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] && [ "$(tool_version "$GH_COMMAND")" = "$GH_VERSION" ]; }
at_prior() { [ "$(head_commit)" = "$PRIOR_COMMIT" ] && [ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_PRIOR" ] && [ "$(tool_version "$GH_COMMAND")" = "$GH_PRIOR" ]; }
no_install_ran() { ! grep -Fq 'install -g' "$NPM_LOG"; }

# --------------------------------- dry-run reports the receipt and writes none

DRY_DIR="$TMP_ROOT/dry-receipts"
json=$(TEST_RECEIPT_DIR="$DRY_DIR" run_tool --dry-run --json)
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = planned ] || fail 'dry-run did not report a planned receipt'
case "$(printf '%s' "$json" | jq -r '.receipt.path')" in
  "$DRY_DIR"/apply-*.json) : ;;
  *) fail 'dry-run did not name the receipt it would have written' ;;
esac
[ ! -e "$DRY_DIR" ] || fail 'dry-run created the receipt directory'
at_prior || fail 'dry-run mutated a tool'
pass 'dry-run names the receipt it would write and writes nothing'

# --------------------------------- a receipt that cannot be written refuses

BLOCKER="$TMP_ROOT/blocker"
: >"$BLOCKER"
: >"$NPM_LOG"
set +e
json=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a receipt that could not be written still exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')" = 'could not write the mutation receipt; refusing to mutate' ] \
  || fail 'Firstmate mutated without a receipt'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')" = 'could not write the mutation receipt; refusing to mutate' ] \
  || fail 'the npm tier mutated without a receipt'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = none ] || fail 'the result claimed a receipt exists'
at_prior || fail 'a tool was changed without a receipt'
no_install_ran || fail 'npm install ran without a receipt'
pass 'a receipt that cannot be written refuses every mutation'

# --------------------------------- the receipt precedes and records the apply

: >"$NPM_LOG"; : >"$PRE_LOG"
json=$(run_tool --json)
RECEIPT=$(printf '%s' "$json" | jq -r '.receipt.path')
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = written ] || fail 'the applied run did not report a written receipt'
[ -f "$RECEIPT" ] || fail 'the reported receipt does not exist'
[ "$(file_mode "$RECEIPT")" = 600 ] || fail "the receipt is not mode 0600: $(file_mode "$RECEIPT")"
[ "$(find "$RECEIPTS" -mindepth 1 | wc -l)" -eq 1 ] || fail 'the receipt directory holds a partial temp file'
grep -Fqx 'git-merge receipt=yes' "$PRE_LOG" || fail 'the Firstmate fast-forward started before a receipt existed'
grep -Fqx 'npm-install receipt=yes' "$PRE_LOG" || fail 'the npm install started before a receipt existed'

fm=$(jq -ce '.tools[] | select(.tier=="firstmate")' "$RECEIPT") || fail 'the receipt omits the Firstmate tool'
[ "$(printf '%s' "$fm" | jq -r '.prior')" = "$PRIOR_COMMIT" ] || fail 'the receipt did not capture the exact prior commit'
[ "$(printf '%s' "$fm" | jq -r '.target')" = "$TARGET_COMMIT" ] || fail 'the receipt did not capture the exact target commit'
[ "$(printf '%s' "$fm" | jq -r '.target_evidence.remote_head')" = "$TARGET_COMMIT" ] || fail 'the receipt did not capture the verified remote evidence'
[ "$(printf '%s' "$fm" | jq -r '.status')" = applied ] || fail 'the receipt did not record Firstmate completion'

np=$(jq -ce '.tools[] | select(.name=="quota-axi")' "$RECEIPT") || fail 'the receipt omits the converged package'
[ "$(printf '%s' "$np" | jq -r '.prior')" = "$QUOTA_PRIOR" ] || fail 'the receipt did not capture the exact prior version'
[ "$(printf '%s' "$np" | jq -r '.target')" = "$QUOTA_VERSION" ] || fail 'the receipt did not capture the exact target version'
[ "$(printf '%s' "$np" | jq -r '.prior_evidence.integrity')" = "$QUOTA_PRIOR_INTEGRITY" ] || fail 'the receipt did not capture prior registry evidence'
[ "$(printf '%s' "$np" | jq -r '.target_evidence.integrity')" = "$QUOTA_INTEGRITY" ] || fail 'the receipt did not capture target registry evidence'
[ "$(printf '%s' "$np" | jq -r '.status')" = applied ] || fail 'the receipt did not record the package completion'

[ "$(jq -r '.tiers.firstmate.status' "$RECEIPT")" = applied ] || fail 'the receipt did not record Firstmate tier completion'
[ "$(jq -r '.tiers.npm_global.status' "$RECEIPT")" = applied ] || fail 'the receipt did not record npm tier completion'
[ "$(jq -r '.rollback.automatic' "$RECEIPT")" = false ] || fail 'the receipt does not declare rollback as never automatic'
[ "$(jq -r '.rollback.restarts_services' "$RECEIPT")" = false ] || fail 'the receipt does not declare rollback as never restarting a service'
converged || fail 'the apply did not converge every tool'
pass 'the receipt is written mode 0600 before mutation and records exact prior, target, and completion'

# --------------------------------- state at the recorded target is eligible

: >"$NPM_LOG"
json=$(run_rollback "$RECEIPT" --json)
[ "$(printf '%s' "$json" | jq -r '.attended')" = false ] || fail 'an unattended rollback claimed to be attended'
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = ready ] || fail "$tool was not eligible while at the recorded target"
done
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="quota-axi") | .observed')" = "$QUOTA_VERSION" ] \
  || fail 'the preflight did not report the observed state'
converged || fail 'the rollback preview mutated a tool'
no_install_ran || fail 'the rollback preview installed a package'
[ "$(jq -r '.tiers.npm_global.status' "$RECEIPT")" = applied ] \
  || fail 'a check-only rollback relabelled a tier that nothing happened to'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = unchanged ] \
  || fail 'a check-only rollback claimed to have settled the receipt'
pass 'an unattended rollback reconciles state at the recorded target and performs nothing'

# --------------------------------- an in-flight lane refuses both tiers

: >"$NPM_LOG"
printf 'lane\n' >"$STATE/active.meta"
set +e
json=$(run_rollback "$RECEIPT" --attended --json)
rc=$?
set -e
rm -f "$STATE/active.meta"
[ "$rc" -ne 0 ] || fail 'an in-flight lane exited successfully'
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_detail "$json" "$tool")" = 'a Firstmate worker lane is in flight' ] \
    || fail "an in-flight lane did not refuse the $tool rollback"
done
converged || fail 'an in-flight lane still mutated a tool'
no_install_ran || fail 'an in-flight lane still reinstalled a package'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = unchanged ] \
  || fail 'an attended reversal that refused every tool still claimed to have settled the receipt'
[ "$(jq -r '.tiers.npm_global.status' "$RECEIPT")" = applied ] \
  || fail 'an attended reversal that changed nothing still rewrote the receipt'
pass 'an in-flight Firstmate lane refuses the npm tier as well as Firstmate and settles nothing'

# --------------------------------- a dirty checkout refuses rollback

printf 'local edit\n' >>"$CHECKOUT/version"
set +e
json=$(run_rollback "$RECEIPT" --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a dirty checkout exited successfully'
[ "$(tool_detail "$json" firstmate)" = 'the checkout has local changes; refusing to discard them' ] || fail 'a dirty checkout was not refused'
[ "$(head_commit)" = "$TARGET_COMMIT" ] || fail 'a dirty checkout was still reset'
git -C "$CHECKOUT" checkout -q -- version
pass 'a dirty checkout refuses rollback instead of discarding the changes'

# --------------------------------- a third version refuses its whole tier

: >"$NPM_LOG"
fake_install "$QUOTA_COMMAND" 9.9.9
WORK=$(work_receipt drift)
set +e
json=$(run_rollback "$WORK" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a third installed version exited successfully'
[ "$(tool_detail "$json" quota-axi)" = 'the current state 9.9.9 matches neither the recorded prior nor the recorded target' ] \
  || fail 'a third installed version was not reported as unreconcilable'
[ "$(tool_status "$json" gh-axi)" = refused ] || fail 'the sibling package in the same tier was still mutated'
[ "$(tool_detail "$json" gh-axi)" = 'another tool in this tier has an unreconcilable state; refusing the whole tier' ] \
  || fail 'the sibling package was refused for the wrong reason'
[ "$(tool_status "$json" firstmate)" = rolled_back ] || fail 'the unrelated Firstmate tier was blocked by npm drift'
no_install_ran || fail 'an unreconcilable tier still installed a package'
[ "$(tool_version "$GH_COMMAND")" = "$GH_VERSION" ] || fail 'the sibling package was reverted despite the tier refusal'
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
fake_install "$QUOTA_COMMAND" "$QUOTA_VERSION"
pass 'a third version refuses every tool in its tier before any of them is changed'

# --------------------------------- absent or unreadable state refuses

: >"$NPM_LOG"
mv "$PREFIX/bin/$GH_COMMAND" "$TMP_ROOT/gh-axi.saved"
WORK=$(work_receipt absent)
set +e
json=$(run_rollback "$WORK" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an absent tool exited successfully'
[ "$(tool_detail "$json" gh-axi)" = 'the current state of this tool is absent or unreadable' ] \
  || fail 'an absent tool was not reported as unreadable'
[ "$(tool_status "$json" quota-axi)" = refused ] || fail 'the sibling package was mutated despite an absent tool'
no_install_ran || fail 'an absent tool still triggered an install'
mv "$TMP_ROOT/gh-axi.saved" "$PREFIX/bin/$GH_COMMAND"
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
pass 'an absent or unreadable tool refuses its tier rather than overwriting it'

# --------------------------------- a command name that leaves the prefix refuses

# The receipt is operator-supplied input by the time a reversal reads it. Its
# recorded command names the executable the npm prefix owns, so a name that walks
# out of the prefix is not observed at all - otherwise an unrelated build there
# could be mistaken for the recorded applied state and reinstalled over.
: >"$NPM_LOG"
mkdir -p "$PREFIX/escape"
printf '#!%s\nprintf "%s %s\\n"\n' "$BASH_BIN" "$QUOTA_COMMAND" "$QUOTA_VERSION" >"$PREFIX/escape/$QUOTA_COMMAND"
chmod +x "$PREFIX/escape/$QUOTA_COMMAND"
ESCAPED="$RECEIPTS/escaped-command.json"
jq --arg c "../escape/$QUOTA_COMMAND" \
  '.tools |= map(if .name=="quota-axi" then .command = $c else . end)' "$RECEIPT" >"$ESCAPED"
set +e
json=$(run_rollback "$ESCAPED" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a recorded command name outside the npm prefix exited successfully'
[ "$(tool_status "$json" quota-axi)" = refused ] \
  || fail 'a recorded command name outside the npm prefix was observed as the installed tool'
no_install_ran || fail 'a recorded command name outside the npm prefix reached a mutation'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] || fail 'the refused escape still changed the tool'
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
pass 'a recorded command name that leaves the npm prefix is never read as installed state'

# --------------------------------- unavailable or changed prior evidence refuses

: >"$NPM_LOG"
unpublish "quota-axi@$QUOTA_PRIOR"
WORK=$(work_receipt evidence)
set +e
json=$(run_rollback "$WORK" --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an unavailable prior version exited successfully'
[ "$(tool_detail "$json" quota-axi)" = "the recorded prior version $QUOTA_PRIOR is no longer available" ] \
  || fail 'an unavailable prior version was not refused'
publish "quota-axi@$QUOTA_PRIOR" sha512-CHANGEDEVIDENCE00000000000000000000000000000000000000000000000000000000000000000000000==
: >"$NPM_LOG"
set +e
json=$(run_rollback "$WORK" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'changed prior integrity exited successfully'
[ "$(tool_detail "$json" quota-axi)" = "the registry integrity for $QUOTA_PRIOR changed since the receipt was written" ] \
  || fail 'changed prior integrity was not refused'
no_install_ran || fail 'a tier with unverifiable prior evidence still reinstalled a package'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] || fail 'a refused artifact still changed the installed version'
# gh-axi sorts before quota-axi in the allowlist, so it is the package that would
# have been reinstalled first if the evidence check ran inside the mutation loop.
[ "$(tool_status "$json" gh-axi)" = refused ] || fail 'the earlier package in the tier was reverted before the later one was verified'
[ "$(tool_version "$GH_COMMAND")" = "$GH_VERSION" ] || fail 'the tier was left half reverted by an unverifiable sibling'
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
pass 'an unavailable or changed prior artifact refuses its whole tier before the first install'

# --------------------------------- attended rollback restores the exact prior

: >"$NPM_LOG"; : >"$LIFECYCLE_LOG"
json=$(run_rollback "$RECEIPT" --attended --json)
[ "$(printf '%s' "$json" | jq -r '.attended')" = true ] || fail 'an attended rollback did not report itself as attended'
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = rolled_back ] || fail "the attended rollback did not complete for $tool"
done
at_prior || fail 'the attended rollback did not restore every recorded prior state'
grep -Fq "install -g quota-axi@$QUOTA_PRIOR" "$NPM_LOG" || fail 'the attended rollback did not reinstall the exact recorded prior version'
[ "$(grep -c 'install -g' "$NPM_LOG")" -eq 2 ] || fail 'the attended rollback installed something the receipt never recorded'
[ ! -s "$LIFECYCLE_LOG" ] || fail 'rollback invoked Herdr or the shared no-mistakes daemon'
settled=$(jq -ce '.tools[] | select(.name=="quota-axi")' "$RECEIPT")
[ "$(printf '%s' "$settled" | jq -r '.status')" = rolled_back ] || fail 'the receipt did not settle the reversal'
[ "$(printf '%s' "$settled" | jq -r '.observed')" = "$QUOTA_PRIOR" ] || fail 'the receipt did not append the observed state'
[ "$(printf '%s' "$settled" | jq -r '.prior')" = "$QUOTA_PRIOR" ] || fail 'the receipt rewrote the recorded prior'
[ "$(printf '%s' "$settled" | jq -r '.target')" = "$QUOTA_VERSION" ] || fail 'the receipt rewrote the recorded target'
[ "$(printf '%s' "$settled" | jq -r '.prior_evidence.integrity')" = "$QUOTA_PRIOR_INTEGRITY" ] || fail 'the receipt rewrote the recorded evidence'
[ "$(jq -r '.tiers.firstmate.status' "$RECEIPT")" = rolled_back ] || fail 'the receipt kept an apply-era Firstmate tier status after the reversal'
[ "$(jq -r '.tiers.npm_global.status' "$RECEIPT")" = rolled_back ] || fail 'the receipt kept an apply-era npm tier status after the reversal'
pass 'an attended rollback restores exactly the recorded prior state and appends the outcome'

# --------------------------------- a settled receipt has nothing left to do

: >"$NPM_LOG"
json=$(run_rollback "$RECEIPT" --attended --json)
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = skipped ] || fail "a settled receipt was re-applied for $tool"
done
at_prior || fail 'rerunning a settled receipt mutated a tool'
no_install_ran || fail 'rerunning a settled receipt installed a package'
pass 'a settled receipt reports nothing left to reverse'

# --------------------------------- an interrupted settle is idempotent

: >"$NPM_LOG"
INTERRUPTED="$RECEIPTS/interrupted.json"
jq '.tools |= map(. + {status:"applied"} | del(.observed, .reconciliation, .reconciled_at))' "$RECEIPT" >"$INTERRUPTED"
json=$(run_rollback "$INTERRUPTED" --attended --json)
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = reconciled ] || fail "an interrupted settle was not reconciled for $tool"
done
at_prior || fail 'retrying an interrupted rollback mutated a tool'
no_install_ran || fail 'retrying an interrupted rollback installed a package'
[ "$(jq -r '.tools[] | select(.name=="quota-axi") | .status' "$INTERRUPTED")" = reconciled_at_prior ] \
  || fail 'the retry did not settle the reconciliation'
[ "$(jq -r '.tools[] | select(.name=="quota-axi") | .prior' "$INTERRUPTED")" = "$QUOTA_PRIOR" ] \
  || fail 'the retry rewrote the recorded prior'
[ "$(jq -r '.tiers.npm_global.status' "$INTERRUPTED")" = reconciled_at_prior ] \
  || fail 'the receipt kept an apply-era tier status after reconciliation'
pass 'retrying a rollback whose settle was interrupted reconciles instead of mutating'

# --------------------------------- a crash before the mutation is reconciled

: >"$NPM_LOG"
CRASH_BEFORE="$RECEIPTS/crash-before.json"
jq '.tools |= map(. + {status:"pending"} | del(.observed, .reconciliation, .reconciled_at))' "$RECEIPT" >"$CRASH_BEFORE"
json=$(run_rollback "$CRASH_BEFORE" --attended --json)
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = reconciled ] || fail "a pending entry at the prior state was not reconciled for $tool"
done
at_prior || fail 'a pending entry at the prior state was still mutated'
no_install_ran || fail 'a pending entry at the prior state still installed a package'
pass 'a receipt left pending by a crash before the mutation is reconciled, not skipped'

# --------------------------------- a crash after the mutation is reversible

: >"$NPM_LOG"
json=$(run_tool --json)
RECEIPT2=$(printf '%s' "$json" | jq -r '.receipt.path')
converged || fail 'the second apply did not converge every tool'
CRASH_AFTER="$RECEIPTS/crash-after.json"
jq '.tools |= map(. + {status:"pending"})' "$RECEIPT2" >"$CRASH_AFTER"
json=$(run_rollback "$CRASH_AFTER" --attended --json)
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = rolled_back ] || fail "a pending entry at the target state was not reversed for $tool"
done
at_prior || fail 'a pending entry at the target state was not reversed'
pass 'a receipt left pending by a crash after the mutation is still reversible'

# --------------------------------- an empty receipt path never runs an apply

: >"$NPM_LOG"
set +e
err=$(run_tool --rollback '' --json 2>&1 >/dev/null)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "an empty --rollback argument did not fail closed (exit $rc)"
printf '%s\n' "$err" | grep -q 'dev-tools-apply-updates: --rollback needs a receipt path' \
  || fail 'an empty --rollback argument refused without a bounded error'
at_prior || fail 'an empty --rollback argument ran a mutating apply'
no_install_ran || fail 'an empty --rollback argument installed a package'
pass 'an empty --rollback argument refuses before the apply dispatch'

# --------------------------------- partial apply is recorded per tool

BEFORE=$(find "$RECEIPTS" -mindepth 1 -name 'apply-*.json' -printf '%f\n')
set +e
human=$(TEST_BAD_INSTALL=1 run_tool)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a partial apply exited successfully'
PARTIAL=""
for candidate in "$RECEIPTS"/apply-*.json; do
  printf '%s\n' "$BEFORE" | grep -Fqx "$(basename "$candidate")" || PARTIAL=$candidate
done
[ -n "$PARTIAL" ] || fail 'the partial apply wrote no receipt'
[ "$(jq -r '.tools[] | select(.tier=="firstmate") | .status' "$PARTIAL")" = applied ] || fail 'the partial receipt lost the applied tool'
[ "$(jq -r '.tools[] | select(.name=="quota-axi") | .status' "$PARTIAL")" = failed ] || fail 'the partial receipt lost the failed tool'
[ "$(jq -r '.tiers.firstmate.status' "$PARTIAL")" = applied ] || fail 'the partial receipt lost the applied tier status'
[ "$(jq -r '.tiers.npm_global.status' "$PARTIAL")" = failed ] || fail 'the partial receipt lost the failed tier status'
[ "$(jq -r '.tools[] | select(.tier=="firstmate") | .prior' "$PARTIAL")" = "$PRIOR_COMMIT" ] \
  || fail 'the partial receipt lost the exact prior commit of the tool that did apply'
printf '%s\n' "$human" | grep -Fq "receipt: $PARTIAL" || fail 'a partial apply did not print the receipt path'
printf '%s\n' "$human" | grep -Fq 'rollback: attended only, never automatic, never restarts a service' \
  || fail 'a partial apply did not print the rollback contract'
printf '%s\n' "$human" | grep -Fq '  preflight: any unreconcilable or unverifiable entry refuses its whole tier' \
  || fail 'a partial apply did not print the reconciliation preconditions'
printf '%s\n' "$human" | grep -Fq '  firstmate: the recorded prior commit must verify as an ancestor of the applied commit' \
  || fail 'a partial apply did not print the exact Firstmate rollback preconditions'
printf '%s\n' "$human" | grep -Fq '  npm_global: only the exact prior version recorded here is reinstalled' \
  || fail 'a partial apply did not print the exact npm rollback preconditions'
printf '%s\n' "$human" | grep -Fq 'the checksum of the operator-supplied artifact' \
  || fail 'a partial apply did not print the exact npm rollback preconditions'
pass 'a partial apply records every tool separately and prints the receipt and its preconditions'

# --------------------------------- a post-install verification failure is reversible

# TEST_BAD_INSTALL replaces the global binary and then reports 0.0.0, so the
# receipt records `failed` for a mutation that really happened. That is a state
# the receipt itself does not name, so it must refuse rather than look settled.
: >"$NPM_LOG"
set +e
json=$(run_rollback "$PARTIAL" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a receipt recording a real mutation as failed exited successfully'
[ "$(tool_detail "$json" quota-axi)" = 'the current state 0.0.0 matches neither the recorded prior nor the recorded target' ] \
  || fail 'a post-install verification failure was reported as nothing left to reverse'
[ "$(tool_status "$json" gh-axi)" = refused ] || fail 'the sibling package was mutated despite an unreconcilable tier'
no_install_ran || fail 'an unreconcilable tier still installed a package'
[ "$(tool_version "$QUOTA_COMMAND")" = 0.0.0 ] || fail 'the refused tier was changed anyway'
pass 'a mutation recorded as failed is reconciled and refuses instead of looking settled'

# --------------------------------- a failed reversal can be retried

fake_install "$QUOTA_COMMAND" "$QUOTA_VERSION"
fake_install "$GH_COMMAND" "$GH_VERSION"
RETRY="$RECEIPTS/retry.json"
jq '.tools |= map(. + {status:"rollback_failed"} | del(.observed, .reconciliation, .reconciled_at))' "$RECEIPT" >"$RETRY"
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
: >"$NPM_LOG"
json=$(run_rollback "$RETRY" --attended --json)
for tool in firstmate quota-axi gh-axi; do
  [ "$(tool_status "$json" "$tool")" = rolled_back ] || fail "a previously failed reversal could not be retried for $tool"
done
at_prior || fail 'retrying a failed reversal did not restore the recorded prior state'
pass 'a reversal recorded as failed can be retried once its cause is fixed'

# --------------------------------- an operator-owned receipt directory is untouched

SHARED="$TMP_ROOT/shared"
mkdir -p "$SHARED"
chmod 755 "$SHARED"
SHARED_RECEIPT="$SHARED/receipt.json"
jq '.tools |= map(. + {status:"applied"} | del(.observed, .reconciliation, .reconciled_at))' "$RECEIPT" >"$SHARED_RECEIPT"
chmod 600 "$SHARED_RECEIPT"
json=$(run_rollback "$SHARED_RECEIPT" --attended --json)
[ "$(tool_status "$json" quota-axi)" = reconciled ] || fail 'the shared-directory receipt was not reconciled'
[ "$(file_mode "$SHARED")" = 755 ] || fail "rollback changed the operator's receipt directory mode to $(file_mode "$SHARED")"
[ "$(file_mode "$SHARED_RECEIPT")" = 600 ] || fail 'the reconciled receipt is no longer mode 0600'
[ "$(jq -r '.tools[] | select(.name=="quota-axi") | .status' "$SHARED_RECEIPT")" = reconciled_at_prior ] \
  || fail 'the shared-directory receipt was not settled in place'
[ "$(find "$SHARED" -mindepth 1 | wc -l)" -eq 1 ] || fail 'rollback left a temp file beside the receipt'
pass 'an attended rollback settles the receipt in place and never changes its parent directory mode'

# --------------------------------- a check-only rollback writes nothing at all

# `--rollback` without `--attended` is documented as check-only, so an archived
# or read-only receipt must survive it byte for byte and must not fail the run.
CHECKONLY="$TMP_ROOT/check-only"
mkdir -p "$CHECKONLY"
ARCHIVED="$CHECKONLY/receipt.json"
jq '.tools |= map(. + {status:"failed"} | del(.observed, .reconciliation, .reconciled_at))
    | .tiers.npm_global.status = "failed" | .tiers.firstmate.status = "failed"' "$RECEIPT" >"$ARCHIVED"
BEFORE=$(cat "$ARCHIVED")
BEFORE_MTIME=$(stat -c '%Y' "$ARCHIVED" 2>/dev/null || stat -f '%m' "$ARCHIVED")
json=$(run_rollback "$ARCHIVED" --json)
[ "$(tool_status "$json" quota-axi)" = reconciled ] || fail 'the check-only run did not report the reconciliation it would record'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = unchanged ] || fail 'a check-only run claimed to have settled the receipt'
[ "$(cat "$ARCHIVED")" = "$BEFORE" ] || fail 'a check-only rollback rewrote the receipt'
[ "$(stat -c '%Y' "$ARCHIVED" 2>/dev/null || stat -f '%m' "$ARCHIVED")" = "$BEFORE_MTIME" ] \
  || fail 'a check-only rollback touched the receipt timestamp'
[ "$(jq -r '.tiers.npm_global.status' "$ARCHIVED")" = failed ] \
  || fail 'a check-only rollback destroyed the recorded apply-era tier status'
[ "$(find "$CHECKONLY" -mindepth 1 | wc -l)" -eq 1 ] || fail 'a check-only rollback left a temp file beside the receipt'

chmod 500 "$CHECKONLY"
set +e
json=$(run_rollback "$ARCHIVED" --json)
rc=$?
set -e
chmod 700 "$CHECKONLY"
[ "$rc" -eq 0 ] || fail "inspecting a read-only receipt exited $rc"
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = unchanged ] \
  || fail 'inspecting a read-only receipt claimed a stale append that was never requested'
pass 'a check-only rollback leaves the receipt and its evidence completely untouched'

# --------------------------------- a receipt that cannot be appended is stale

# The git stub turns the receipt's own directory into a regular file once the
# tool has read the receipt, so the write-back fails for every uid.
seed_stale_receipt() {
  rm -rf "$UNWRITABLE"
  mkdir -p "$UNWRITABLE"
  jq '.tools |= map(. + {status:"applied"} | del(.observed, .reconciliation, .reconciled_at))' "$RECEIPT" >"$STALE_RECEIPT"
}
UNWRITABLE="$TMP_ROOT/unwritable"
STALE_RECEIPT="$UNWRITABLE/receipt.json"
TEST_BREAK_RECEIPT_DIR="$UNWRITABLE"
seed_stale_receipt
set +e
json=$(run_rollback "$STALE_RECEIPT" --attended --json)
rc=$?
seed_stale_receipt
human=$(run_rollback "$STALE_RECEIPT" --attended 2>&1)
set -e
unset TEST_BREAK_RECEIPT_DIR
[ "$rc" -ne 0 ] || fail 'a receipt that could not be appended exited successfully'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = stale ] || fail 'a failed receipt append was not reported as stale'
[ ! -d "$UNWRITABLE" ] || fail 'the fault injection did not actually make the receipt directory unusable'
printf '%s\n' "$human" | grep -Fq 'receipt is stale' || fail 'human output did not warn about the stale receipt'
rm -f "$UNWRITABLE"
pass 'an attended reversal whose receipt append fails reports a stale receipt and exits non-zero'

# --------------------------------- unusable receipts fail closed

assert_receipt_refused() { # label, path
  local rc=0
  set +e
  run_rollback "$2" --json >/dev/null 2>"$TMP_ROOT/receipt.err"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "$1 did not fail closed (exit $rc)"
  grep -q 'dev-tools-apply-updates:' "$TMP_ROOT/receipt.err" || fail "$1 refused without a bounded error"
}
printf 'not json\n' >"$TMP_ROOT/garbage.json"
assert_receipt_refused 'an unparseable receipt' "$TMP_ROOT/garbage.json"
printf '{"schema_version":99,"tools":[]}\n' >"$TMP_ROOT/foreign.json"
assert_receipt_refused 'a foreign receipt document' "$TMP_ROOT/foreign.json"
assert_receipt_refused 'an absent receipt' "$TMP_ROOT/does-not-exist.json"
pass 'a missing, unparseable, or foreign receipt is refused before any rollback'

# --------------------------------- an unrecordable outcome is reported

# The stub destroys the receipt directory during `npm install -g`, so the
# mutation succeeds but the settle that follows it cannot be written - the same
# shape as a full disk or a directory that lost write permission mid-run.
reset_to_prior() {
  git -C "$CHECKOUT" reset -q --hard "$PRIOR_COMMIT"
  fake_install "$QUOTA_COMMAND" "$QUOTA_PRIOR"
  fake_install "$GH_COMMAND" "$GH_PRIOR"
  rm -rf "$RECEIPTS"
  mkdir -p "$RECEIPTS"
}

reset_to_prior
set +e
json=$(TEST_BREAK_RECEIPT=quota-axi run_tool --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an unrecordable outcome exited successfully'
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = incomplete ] || fail 'an unrecordable outcome was not reported as incomplete'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = applied ] \
  || fail 'the test fixture did not actually converge the tool it failed to record'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] || fail 'the fixture did not really mutate the tool'

reset_to_prior
set +e
human=$(TEST_BREAK_RECEIPT=quota-axi run_tool 2>"$TMP_ROOT/incomplete.err")
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an unrecordable outcome exited successfully in human mode'
printf '%s\n' "$human" | grep -Eq 'receipt: .* \(incomplete\)' || fail 'human output did not report the incomplete receipt'
printf '%s\n' "$human" | grep -Fq 'rollback: attended only, never automatic, never restarts a service' \
  || fail 'human output dropped the rollback preconditions for an incomplete receipt'
grep -q 'receipt is incomplete' "$TMP_ROOT/incomplete.err" || fail 'human output did not warn about the incomplete receipt'
rm -f "$RECEIPTS"
mkdir -p "$RECEIPTS"
pass 'an outcome that cannot be recorded is reported as incomplete and exits non-zero'

# --------------------------------- an operator-supplied receipt directory is theirs

OPERATOR_DIR="$TMP_ROOT/operator-receipts"
mkdir -p "$OPERATOR_DIR"
chmod 755 "$OPERATOR_DIR"
reset_to_prior
json=$(TEST_RECEIPT_DIR="$OPERATOR_DIR" run_tool --json)
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = written ] || fail 'the apply did not write into the operator directory'
[ "$(file_mode "$OPERATOR_DIR")" = 755 ] \
  || fail "the apply changed the operator's receipt directory mode to $(file_mode "$OPERATOR_DIR")"
OPERATOR_RECEIPT=$(printf '%s' "$json" | jq -r '.receipt.path')
[ "$(file_mode "$OPERATOR_RECEIPT")" = 600 ] || fail 'the receipt itself is not mode 0600'
converged || fail 'the operator-directory run did not converge'

# A receipt location that is not a directory at all is unusable for every uid.
UNUSABLE_DIR="$TMP_ROOT/unusable-receipts"
rm -rf "$UNUSABLE_DIR"
: >"$UNUSABLE_DIR"
reset_to_prior
set +e
json=$(TEST_RECEIPT_DIR="$UNUSABLE_DIR" run_tool --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an unusable receipt directory exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')" = 'could not write the mutation receipt; refusing to mutate' ] \
  || fail 'an unusable receipt directory did not refuse the mutation'
at_prior || fail 'an unusable receipt directory still mutated a tool'
rm -f "$UNUSABLE_DIR"

# A directory the run has to create is created and secured privately.
CREATED_DIR="$TMP_ROOT/created/receipts"
rm -rf "$TMP_ROOT/created"
reset_to_prior
json=$(TEST_RECEIPT_DIR="$CREATED_DIR" run_tool --json)
[ "$(printf '%s' "$json" | jq -r '.receipt.status')" = written ] || fail 'the apply did not create its own receipt directory'
[ "$(file_mode "$CREATED_DIR")" = 700 ] || fail "a directory the run created is not private: $(file_mode "$CREATED_DIR")"
pass 'the apply secures only a directory it creates and refuses an unusable location'

# --------------------------------- the preview refuses what the apply refuses

# The reversal-path gate has to run before the preview reports, or the operator
# is told `would_apply` for a mutation the very next run refuses.
reset_to_prior
unpublish "quota-axi@$QUOTA_PRIOR"
set +e
dry=$(run_tool --dry-run --json)
dry_rc=$?
json=$(run_tool --json)
apply_rc=$?
set -e
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
[ "$dry_rc" -eq "$apply_rc" ] || fail "the preview exited $dry_rc but the apply exited $apply_rc"
[ "$(package_status "$dry" quota-axi)" = "$(package_status "$json" quota-axi)" ] \
  || fail "the preview said $(package_status "$dry" quota-axi) but the apply said $(package_status "$json" quota-axi)"
[ "$(package_detail "$dry" quota-axi)" = "$(package_detail "$json" quota-axi)" ] \
  || fail 'the preview and the apply gave different reasons for the same unrecordable mutation'
pass 'a mutation with no reversal path is refused identically by the preview and the apply'

# --------------------------------- an operator-supplied artifact restores it

# The installed version is not in the registry, so the operator supplies exactly
# that artifact; its checksum becomes the recorded evidence and the file is what
# a reversal reinstalls.
ARTIFACTS="$TMP_ROOT/artifacts"
mkdir -p "$ARTIFACTS"
make_artifact() { # file-package, file-version, manifest-name, manifest-version
  local dir
  dir=$(mktemp -d "$TMP_ROOT/pack.XXXXXX")
  mkdir -p "$dir/package"
  printf '{"name":"%s","version":"%s"}\n' "${3:-$1}" "${4:-$2}" >"$dir/package/package.json"
  tar -czf "$ARTIFACTS/$1-$2.tgz" -C "$dir" package
  rm -rf "$dir"
}
make_artifact quota-axi "$QUOTA_PRIOR"
cp "$ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz" "$TMP_ROOT/artifact.original"
reset_to_prior
unpublish "quota-axi@$QUOTA_PRIOR"
TEST_ARTIFACT_DIR="$ARTIFACTS"
set +e
json=$(run_tool --json)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "an operator-supplied artifact did not unblock the mutation (exit $rc): $(package_detail "$json" quota-axi)"
[ "$(package_status "$json" quota-axi)" = applied ] || fail 'an operator-supplied artifact did not unblock the mutation'
ARTIFACT_RECEIPT=$(printf '%s' "$json" | jq -r '.receipt.path')
entry=$(jq -ce '.tools[] | select(.name=="quota-axi")' "$ARTIFACT_RECEIPT")
[ "$(printf '%s' "$entry" | jq -r '.prior_evidence.kind')" = operator-artifact ] || fail 'the receipt did not record the artifact evidence'
[ "$(printf '%s' "$entry" | jq -r '.prior_evidence.path')" = "$ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz" ] \
  || fail 'the receipt did not record the artifact path'
RECORDED_SUM=$(printf '%s' "$entry" | jq -r '.prior_evidence.checksum')
[ "$RECORDED_SUM" = "sha256-$(sha256sum "$ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz" | cut -d' ' -f1)" ] \
  || fail 'the receipt did not record the artifact checksum'

# A changed artifact is refused, exactly like changed registry evidence.
printf 'tampered\n' >>"$ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz"
set +e
json=$(run_rollback "$ARTIFACT_RECEIPT" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a changed prior artifact exited successfully'
[ "$(tool_detail "$json" quota-axi)" = "the recorded prior artifact $ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz changed since the receipt was written" ] \
  || fail "a changed prior artifact was not refused: $(tool_detail "$json" quota-axi)"
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] || fail 'a changed prior artifact was still reinstalled'

# Restored to what the receipt recorded, the reversal installs from that file.
cp "$TMP_ROOT/artifact.original" "$ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz"
: >"$NPM_LOG"
json=$(run_rollback "$ARTIFACT_RECEIPT" --attended --json)
[ "$(tool_status "$json" quota-axi)" = rolled_back ] || fail 'an operator-supplied artifact could not be reversed'
grep -Fq "install -g $ARTIFACTS/quota-axi-$QUOTA_PRIOR.tgz" "$NPM_LOG" \
  || fail 'the reversal did not reinstall the recorded artifact file'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_PRIOR" ] || fail 'the reversal did not restore the prior version'
unset TEST_ARTIFACT_DIR
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
pass 'an operator-supplied artifact is the recovery: recorded, re-verified, and reinstalled'

# --------------------------------- an unrecordable reversal path refuses

# The installed version is gone from the registry, so no prior evidence can be
# captured for it. Installing anyway would leave the tool irreversible.
reset_to_prior
unpublish "quota-axi@$QUOTA_PRIOR"
: >"$NPM_LOG"
set +e
json=$(run_tool --json)
rc=$?
set -e
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
[ "$rc" -ne 0 ] || fail 'a mutation with no reversal path exited successfully'
[ "$(package_status "$json" quota-axi)" = refused ] || fail 'a mutation with no reversal path was not refused'
case "$(package_detail "$json" quota-axi)" in
  "could not verify the installed version $QUOTA_PRIOR against the registry or an operator-supplied artifact;"*) : ;;
  *) fail "an unrecordable mutation was refused for the wrong reason: $(package_detail "$json" quota-axi)" ;;
esac
! grep -Fq "install -g quota-axi@$QUOTA_VERSION" "$NPM_LOG" || fail 'a package with no reversal path was still installed'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_PRIOR" ] || fail 'a package with no reversal path was still changed'

# The sibling with good evidence converges, and the receipt it produced is still
# fully reversible - one tool's missing evidence must not poison the tier.
[ "$(package_status "$json" gh-axi)" = applied ] || fail 'the sibling package was blocked by an unrelated missing evidence'
PARTIAL_RECEIPT=$(printf '%s' "$json" | jq -r '.receipt.path')
[ "$(jq -r '[.tools[] | select(.name=="quota-axi")] | length' "$PARTIAL_RECEIPT")" -eq 0 ] \
  || fail 'the receipt recorded a tool that was never mutated'
[ "$(jq -r '.tools[] | select(.name=="gh-axi") | .prior_evidence.integrity' "$PARTIAL_RECEIPT")" = "$GH_PRIOR_INTEGRITY" ] \
  || fail 'the receipt lost the sibling prior evidence'
json=$(run_rollback "$PARTIAL_RECEIPT" --attended --json)
[ "$(tool_status "$json" gh-axi)" = rolled_back ] || fail 'the receipt from a partly refused apply was not reversible'
[ "$(tool_version "$GH_COMMAND")" = "$GH_PRIOR" ] || fail 'the sibling package was not restored'
pass 'an npm mutation whose reversal path cannot be recorded is refused, and its siblings stay reversible'

# --------------------------------- an unguarded allowlisted name says so

# The hard allowlist and the guarded manifest rows are meant to agree; when a
# manifest edit desynchronises them the tier refuses, and the package that
# caused it has to be findable in the emitted list.
UNGUARDED_PINS="$TMP_ROOT/unguarded-pins.sh"
sed '/lavish-axi/s/|yes|/|no|/' "$PINS" >"$UNGUARDED_PINS"
[ "$(grep -c 'lavish-axi.*|no|' "$UNGUARDED_PINS")" -eq 1 ] || fail 'the unguarded-pin fixture did not flip exactly one row'
reset_to_prior
SAFE_PINS=$PINS
PINS=$UNGUARDED_PINS
set +e
json=$(run_tool --json)
rc=$?
set -e
PINS=$SAFE_PINS
[ "$rc" -ne 0 ] || fail 'a desynchronised allowlist exited successfully'
[ "$(package_status "$json" lavish-axi)" = refused ] \
  || fail "an allowlisted name with no guarded pin was not reported as refused: $(package_status "$json" lavish-axi)"
[ "$(printf '%s' "$json" | jq -r '[.tiers.npm_global.packages[] | select(.status=="refused")] | length')" -ge 1 ] \
  || fail 'the tier refused but no package in the list carries the refusal'
pass 'an allowlisted name with no guarded pin reports its own refusal'

# --------------------------------- a mislabelled artifact is not evidence

# `npm install -g <tarball>` installs whatever the tarball contains, so the
# filename alone cannot be the reversal path.
reset_to_prior
unpublish "quota-axi@$QUOTA_PRIOR"
make_artifact quota-axi "$QUOTA_PRIOR" lavish-axi 0.1.60
TEST_ARTIFACT_DIR="$ARTIFACTS"
: >"$NPM_LOG"
set +e
json=$(run_tool --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an artifact naming a different package exited successfully'
[ "$(package_status "$json" quota-axi)" = refused ] || fail 'an artifact naming a different package was accepted as evidence'
! grep -Fq "install -g quota-axi@$QUOTA_VERSION" "$NPM_LOG" || fail 'a mutation ran on unverified artifact evidence'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_PRIOR" ] || fail 'the tool was changed on unverified artifact evidence'
make_artifact quota-axi "$QUOTA_PRIOR"
unset TEST_ARTIFACT_DIR
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
pass 'an artifact whose own manifest names another package is refused, not recorded'

# --------------------------------- an unrestorable version shape is refused

# The rollback preflight and the installed-version observer both accept only
# X.Y.Z; recording anything else as the prior version would be a dead end.
reset_to_prior
TEST_QUOTA_CURRENT=0.1.42-rc1
set +e
dry=$(run_tool --dry-run --json)
dry_rc=$?
json=$(run_tool --json)
apply_rc=$?
set -e
unset TEST_QUOTA_CURRENT
[ "$apply_rc" -ne 0 ] || fail 'a prerelease installed version exited successfully'
[ "$(package_status "$json" quota-axi)" = refused ] || fail 'a prerelease installed version was recorded as reversible'
case "$(package_detail "$json" quota-axi)" in
  'the installed version 0.1.42-rc1 has no shape a reversal could restore;'*) : ;;
  *) fail "a prerelease installed version was refused for the wrong reason: $(package_detail "$json" quota-axi)" ;;
esac
[ "$dry_rc" -eq "$apply_rc" ] || fail "the preview exited $dry_rc but the apply exited $apply_rc"
[ "$(package_detail "$dry" quota-axi)" = "$(package_detail "$json" quota-axi)" ] \
  || fail 'the preview and the apply disagreed on an unrestorable version shape'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_PRIOR" ] || fail 'a prerelease installed version was still mutated'
pass 'an installed version the rollback could never restore is refused by both directions'

# --------------------------------- the preview answers the receipt question too

# The apply refuses every mutation when the receipt cannot be written; a preview
# that reported would_apply here would send the operator into that refusal.
reset_to_prior
set +e
dry=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --dry-run --json)
dry_rc=$?
json=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --json)
apply_rc=$?
set -e
[ "$dry_rc" -eq "$apply_rc" ] || fail "the preview exited $dry_rc but the apply exited $apply_rc on an unusable receipt location"
[ "$(printf '%s' "$dry" | jq -r '.receipt.status')" = unusable ] \
  || fail "a preview with an unusable receipt location still claimed a planned receipt: $(printf '%s' "$dry" | jq -r '.receipt.status')"
for tier in firstmate npm_global; do
  [ "$(printf '%s' "$dry" | jq -r --arg t "$tier" '.tiers[$t].detail')" = "$(printf '%s' "$json" | jq -r --arg t "$tier" '.tiers[$t].detail')" ] \
    || fail "the preview and the apply disagreed on $tier for an unusable receipt location"
done
at_prior || fail 'a preview with an unusable receipt location mutated a tool'

# Human mode is what the operator reads, so the cause has to be there too: the
# per-package detail that names it lives only in the JSON packages array.
set +e
human=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --dry-run)
human_rc=$?
set -e
[ "$human_rc" -eq "$dry_rc" ] || fail "human dry-run exited $human_rc but JSON dry-run exited $dry_rc"
printf '%s\n' "$human" | grep -Fq "receipt: $BLOCKER/receipts/" \
  || fail 'human dry-run did not name the receipt it could not write'
printf '%s\n' "$human" | grep -Fq '(unusable; the receipt could not be written there)' \
  || fail 'human dry-run did not report the receipt as unusable'
printf '%s\n' "$human" | grep -Fq 'npm_global is refused for that reason, not for its own state' \
  || fail 'human dry-run did not tie the refused tier to the unusable receipt'
pass 'a receipt location the apply could not write is refused by the preview too, in both output modes'

# --------------------------------- an unusable receipt claims only its own tiers

# The receipt is unwritable and the npm tier is refused for a different reason
# entirely, so the receipt line must not claim credit for that refusal.
# Firstmate is already at its pin, so it never reaches the receipt gate; only the
# npm tier refuses, and for missing prior evidence rather than for the receipt.
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
fake_install "$QUOTA_COMMAND" "$QUOTA_PRIOR"
fake_install "$GH_COMMAND" "$GH_VERSION"
unpublish "quota-axi@$QUOTA_PRIOR"
rm -rf "$RECEIPTS"; mkdir -p "$RECEIPTS"
set +e
human=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --dry-run)
json=$(TEST_RECEIPT_DIR="$BLOCKER/receipts" run_tool --dry-run --json)
set -e
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = up_to_date ] \
  || fail 'the fixture did not leave Firstmate outside the receipt gate'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = refused ] \
  || fail 'the fixture did not refuse the npm tier for its own reason'
printf '%s\n' "$human" | grep -Fq '(unusable; the receipt could not be written there)' \
  || fail 'the unusable receipt was not reported'
printf '%s\n' "$human" | grep -Fq 'is refused for that reason, not for its own state' \
  && fail 'the receipt claimed a refusal that was caused by something else'
pass 'an unusable receipt only claims the tiers it actually refused'

# --------------------------------- a reversal reports its own refusal reason

# The prior version is retired between the tier preflight and the per-tool
# re-verification, so the reason the operator sees has to be the real one.
reset_to_prior
: >"$NPM_LOG"
json=$(run_tool --json)
RETIRE_RECEIPT=$(printf '%s' "$json" | jq -r '.receipt.path')
converged || fail 'the fixture apply did not converge'
set +e
json=$(TEST_RETIRE_AFTER_VIEW="quota-axi@$QUOTA_PRIOR" run_rollback "$RETIRE_RECEIPT" --attended --json)
rc=$?
set -e
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
[ "$rc" -ne 0 ] || fail 'a prior version retired mid-rollback exited successfully'
[ "$(tool_detail "$json" quota-axi)" = "the recorded prior version $QUOTA_PRIOR is no longer available" ] \
  || fail "the reversal substituted a reason for the one its own preflight produced: $(tool_detail "$json" quota-axi)"
pass 'a reversal reports the refusal reason its own re-verification produced'

printf '\nall dev-tools-apply-updates receipt and rollback tests passed\n'
