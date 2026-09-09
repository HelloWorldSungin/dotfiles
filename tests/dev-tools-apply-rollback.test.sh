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
    current=\$(env NO_UPDATE_NOTIFIER=1 "\$TEST_PREFIX/bin/\$command_name" --version 2>/dev/null | grep -Eo '[0-9]+(\\.[0-9]+){2,3}' | head -1)
  fi
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
    exit 0
  fi
  exit 1
fi
if [ "\$1" = install ]; then
  if ls "\$TEST_RECEIPT_DIR"/apply-*.json >/dev/null 2>&1; then printf 'npm-install receipt=yes\n' >>"\$TEST_PRE_LOG"
  else printf 'npm-install receipt=no\n' >>"\$TEST_PRE_LOG"; fi
  spec=\$3
  package=\${spec%@*}
  version=\${spec##*@}
  for row in "\${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r _name command_name candidate pinned _integrity guarded _channel <<<"\$row"
    [ "\$guarded" = yes ] || continue
    [ "\$candidate" = "\$package" ] || continue
    reported=\$version
    [ "\${TEST_BAD_INSTALL:-0}" = 1 ] && [ "\$version" = "\$pinned" ] && reported=0.0.0
    mkdir -p "\$NPM_CONFIG_PREFIX/bin"
    printf '#!$BASH_BIN\nprintf "%s %s\\\\n"\n' "\$command_name" "\$reported" >"\$NPM_CONFIG_PREFIX/bin/\$command_name"
    chmod +x "\$NPM_CONFIG_PREFIX/bin/\$command_name"
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
    TEST_RECEIPT_DIR="${TEST_RECEIPT_DIR:-$RECEIPTS}" TEST_BAD_INSTALL="${TEST_BAD_INSTALL:-0}" \
    "$APPLY" "$@"
}
run_rollback() { run_tool --rollback "$1" "${@:2}"; }

work_receipt() { cp "$RECEIPT" "$RECEIPTS/work-$1.json"; printf '%s\n' "$RECEIPTS/work-$1.json"; }
head_commit() { git -C "$CHECKOUT" rev-parse HEAD; }
tool_version() { env NO_UPDATE_NOTIFIER=1 "$PREFIX/bin/$1" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){2,3}' | head -1; }
tool_status() { printf '%s' "$1" | jq -r --arg n "$2" '.tools[] | select(.name==$n) | .status'; }
tool_detail() { printf '%s' "$1" | jq -r --arg n "$2" '.tools[] | select(.name==$n) | .detail'; }
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
pass 'an in-flight Firstmate lane refuses the npm tier as well as Firstmate'

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
set +e
json=$(run_rollback "$WORK" --attended --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'changed prior integrity exited successfully'
[ "$(tool_detail "$json" quota-axi)" = "the registry integrity for $QUOTA_PRIOR changed since the receipt was written" ] \
  || fail 'changed prior integrity was not refused'
! grep -Fq "install -g quota-axi@$QUOTA_PRIOR" "$NPM_LOG" || fail 'a refused artifact was still reinstalled'
[ "$(tool_version "$QUOTA_COMMAND")" = "$QUOTA_VERSION" ] || fail 'a refused artifact still changed the installed version'
publish "quota-axi@$QUOTA_PRIOR" "$QUOTA_PRIOR_INTEGRITY"
git -C "$CHECKOUT" reset -q --hard "$TARGET_COMMIT"
fake_install "$GH_COMMAND" "$GH_VERSION"
pass 'rollback refuses an unavailable or changed prior artifact before reinstalling'

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
printf '%s\n' "$human" | grep -Fq '  preflight: any other state - a third version, a moved commit, an absent or unreadable tool - refuses that whole tier' \
  || fail 'a partial apply did not print the reconciliation preconditions'
printf '%s\n' "$human" | grep -Fq '  firstmate: the recorded prior commit must verify as an ancestor of the applied commit' \
  || fail 'a partial apply did not print the exact Firstmate rollback preconditions'
printf '%s\n' "$human" | grep -Fq '  npm_global: only the exact prior version recorded here is reinstalled' \
  || fail 'a partial apply did not print the exact npm rollback preconditions'
pass 'a partial apply records every tool separately and prints the receipt and its preconditions'

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

printf '\nall dev-tools-apply-updates receipt and rollback tests passed\n'
