#!/usr/bin/env bash
# Behavior tests for the Firstmate dry-run preview.
#
# The preview has to answer the same question the real run answers, from the
# same remote, without touching the checkout. Every case runs the real tool
# against local git fixtures and a stub checker; no live tool, package, remote,
# or service is touched.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLY="$ROOT/bin/dev-tools-apply-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-apply-dry-run-tests.XXXXXX")
trap 'chmod -R u+rwX "$TMP_ROOT" 2>/dev/null; rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

BASH_BIN=$(command -v bash) || fail 'missing test dependency: bash'
REAL_GIT=$(command -v git) || fail 'missing test dependency: git'
git_c() { "$REAL_GIT" -C "$1" -c user.email=tests@example.invalid -c user.name=tests "${@:2}"; }

# ------------------------------------------------------------------ fixtures

SEED="$TMP_ROOT/seed"; REMOTE="$TMP_ROOT/origin.git"; CHECKOUT="$TMP_ROOT/firstmate"
mkdir -p "$SEED"
git_c "$SEED" init -q -b main
printf 'one\n' >"$SEED/version"
git_c "$SEED" add version
git_c "$SEED" commit -qm one
BASE_COMMIT=$("$REAL_GIT" -C "$SEED" rev-parse HEAD)
"$REAL_GIT" clone -q --bare "$SEED" "$REMOTE"
"$REAL_GIT" clone -q "file://$REMOTE" "$CHECKOUT"
printf 'two\n' >>"$SEED/version"
git_c "$SEED" commit -qam two
AHEAD_COMMIT=$("$REAL_GIT" -C "$SEED" rev-parse HEAD)
git_c "$SEED" push -q "file://$REMOTE" main

PINS="$TMP_ROOT/pins.sh"
STATE="$TMP_ROOT/state"; PREFIX="$TMP_ROOT/npm-prefix"; FAKEBIN="$TMP_ROOT/fakebin"
RECEIPTS="$TMP_ROOT/receipts"
mkdir -p "$STATE" "$PREFIX/bin" "$FAKEBIN" "$RECEIPTS" "$TMP_ROOT/home"
GIT_LOG="$TMP_ROOT/git.log"; : >"$GIT_LOG"

write_pins() { # firstmate rev
  cp "$ROOT/config/dev-tools-versions.sh" "$PINS"
  printf '\nFIRSTMATE_REV=%s\n' "$1" >>"$PINS"
}

# The npm tier is out of scope here: every allowlisted tool reports its own pin,
# so only the Firstmate tier can move.
cat >"$FAKEBIN/checker" <<SH
#!$BASH_BIN
set -eu
# shellcheck source=/dev/null
source "\$TEST_PINS"
head=\$($REAL_GIT -C "\$TEST_FIRSTMATE" rev-parse HEAD)
tools=\$(jq -cn --arg current "\$head" --arg pin "\$FIRSTMATE_REV" \\
  '[{name:"firstmate",current:\$current,pinned:\$pin,latest_stable:\$pin,status:(if \$current==\$pin then "up_to_date" else "drifted" end)}]')
for row in "\${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name _command_name _package pinned _integrity guarded _channel <<<"\$row"
  [ "\$guarded" = yes ] || continue
  item=\$(jq -cn --arg n "\$name" --arg p "\$pinned" '{name:\$n,current:\$p,pinned:\$p,latest_stable:\$p,status:"up_to_date"}')
  tools=\$(jq -cn --argjson t "\$tools" --argjson i "\$item" '\$t+[\$i]')
done
jq -cn --argjson tools "\$tools" '{schema_version:4,tools:\$tools}'
SH

# Records every git invocation so the fetch URL and refspec can be compared
# against the ones the real apply path uses, then runs the real git.
cat >"$FAKEBIN/git" <<SH
#!$BASH_BIN
printf '%s\n' "\$*" >>"\$TEST_GIT_LOG"
# Locks the temp parent mid-probe so the tool's own cleanup is what fails.
if [ -n "\${TEST_LOCK_TMPDIR:-}" ]; then
  case "\$*" in *ls-remote*) chmod 500 "\$TEST_LOCK_TMPDIR" 2>/dev/null || true ;; esac
fi
exec $REAL_GIT "\$@"
SH
chmod +x "$FAKEBIN"/*

run_tool() {
  env HOME="$TMP_ROOT/home" PATH="$FAKEBIN:/usr/bin:/bin" DEV_TOOLS_PINS_FILE="$PINS" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$FAKEBIN/checker" DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" \
    DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" DEV_TOOLS_FIRSTMATE_REPO="${TEST_REPO:-file://$REMOTE}" \
    DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" DEV_TOOLS_UPDATE_GIT_BIN="$FAKEBIN/git" \
    DEV_TOOLS_APPLY_RECEIPT_DIR="$RECEIPTS" TEST_PINS="$PINS" TEST_FIRSTMATE="$CHECKOUT" \
    TEST_GIT_LOG="$GIT_LOG" TMPDIR="${TEST_TMPDIR:-$TMP_ROOT/tmp}" \
    TEST_LOCK_TMPDIR="${TEST_LOCK_TMPDIR:-}" \
    "$APPLY" "$@"
}
mkdir -p "$TMP_ROOT/tmp"

firstmate_status() { printf '%s' "$1" | jq -r '.tiers.firstmate.status'; }
firstmate_detail() { printf '%s' "$1" | jq -r '.tiers.firstmate.detail'; }
head_commit() { "$REAL_GIT" -C "$CHECKOUT" rev-parse HEAD; }

# A snapshot of everything a fetch into the real checkout would move.
checkout_fingerprint() {
  "$REAL_GIT" -C "$CHECKOUT" for-each-ref --format='%(refname) %(objectname)'
  "$REAL_GIT" -C "$CHECKOUT" rev-parse HEAD
  "$REAL_GIT" -C "$CHECKOUT" status --porcelain
  "$REAL_GIT" -C "$CHECKOUT" config --local --list | sort
  find "$CHECKOUT/.git" -maxdepth 1 | sort
}

# Runs in this shell so DRY_RC survives; a command substitution would discard it.
DRY_JSON=
DRY_RC=0
dry_run() {
  set +e
  DRY_JSON=$(run_tool --dry-run --json)
  DRY_RC=$?
  set -e
}

# ------------------------- a pin that is not fetched locally is still previewed

write_pins "$AHEAD_COMMIT"
[ "$(head_commit)" = "$BASE_COMMIT" ] || fail 'the fixture checkout is not at the base commit'
"$REAL_GIT" -C "$CHECKOUT" cat-file -e "$AHEAD_COMMIT^{commit}" 2>/dev/null &&
  fail 'the fixture already fetched the pin, so it cannot exercise the pending-update case'
BEFORE=$(checkout_fingerprint)
: >"$GIT_LOG"
dry_run; json=$DRY_JSON
[ "$DRY_RC" -eq 0 ] || fail "a clean fast-forward preview exited $DRY_RC"
[ "$(firstmate_status "$json")" = would_apply ] \
  || fail "a pending update was not previewed as would_apply: $(firstmate_status "$json") - $(firstmate_detail "$json")"
[ "$(checkout_fingerprint)" = "$BEFORE" ] || fail 'the dry-run wrote to the real Firstmate checkout'
[ ! -e "$CHECKOUT/.git/FETCH_HEAD" ] || fail 'the dry-run left a FETCH_HEAD in the real checkout'
[ "$(find "$TMP_ROOT/tmp" -mindepth 1 | wc -l)" -eq 0 ] || fail 'the dry-run left its private temporary state behind'
pass 'a pin that is not present locally is previewed as a clean fast-forward'

# ------------------------- the preview matches what the apply then does

json=$(run_tool --json)
[ "$(firstmate_status "$json")" = applied ] || fail 'the apply did not converge after the preview said it would'
[ "$(head_commit)" = "$AHEAD_COMMIT" ] || fail 'the apply did not move the checkout to the pin'
grep -Fq "ls-remote file://$REMOTE refs/heads/main" "$GIT_LOG" || fail 'the apply used a different remote or ref'
grep -Fq -- "--git-dir=$TMP_ROOT/tmp" "$GIT_LOG" || fail 'the dry-run did not use private temporary git state'
grep -Eq -- "--git-dir=.* fetch --quiet --no-tags file://$REMOTE \+refs/heads/main:refs/dev-tools/remote" "$GIT_LOG" \
  || fail 'the dry-run fetched a different URL or refspec than the apply path uses'
pass 'the preview and the apply read the same remote and reach the same conclusion'

# ------------------------- equality is reported as up to date

dry_run; json=$DRY_JSON
[ "$DRY_RC" -eq 0 ] || fail "an up-to-date preview exited $DRY_RC"
[ "$(firstmate_status "$json")" = up_to_date ] || fail 'a converged checkout was not previewed as up_to_date'
pass 'a checkout already at the pin is previewed as up to date'

# ------------------------- a checkout ahead of the pin is refused

write_pins "$BASE_COMMIT"
dry_run; json=$DRY_JSON
[ "$DRY_RC" -ne 0 ] || fail 'a checkout ahead of the pin exited successfully'
[ "$(firstmate_status "$json")" = refused ] || fail 'a checkout ahead of the pin was not refused'
[ "$(firstmate_detail "$json")" = 'the local default branch is ahead of the exact pin' ] \
  || fail "a checkout ahead of the pin was refused for the wrong reason: $(firstmate_detail "$json")"
[ "$(head_commit)" = "$AHEAD_COMMIT" ] || fail 'a refused preview moved the checkout'
pass 'a checkout ahead of the exact pin is refused, not previewed as applyable'

# ------------------------- a diverged checkout is refused

git_c "$SEED" checkout -q -b sidebranch "$BASE_COMMIT"
printf 'side\n' >>"$SEED/version"
git_c "$SEED" commit -qam side
DIVERGED_COMMIT=$("$REAL_GIT" -C "$SEED" rev-parse HEAD)
git_c "$SEED" push -q "file://$REMOTE" "sidebranch:main" --force
write_pins "$DIVERGED_COMMIT"
dry_run; json=$DRY_JSON
[ "$DRY_RC" -ne 0 ] || fail 'a diverged checkout exited successfully'
[ "$(firstmate_status "$json")" = refused ] || fail 'a diverged checkout was not refused'
[ "$(firstmate_detail "$json")" = 'the local default branch has diverged from the exact pin' ] \
  || fail "a diverged checkout was refused for the wrong reason: $(firstmate_detail "$json")"
pass 'a checkout diverged from the exact pin is refused'

# ------------------------- a pin the remote does not carry is refused

git_c "$SEED" checkout -q main
git_c "$SEED" push -q "file://$REMOTE" "main:main" --force
write_pins "$(printf '%040d' 0 | tr 0 a)"
dry_run; json=$DRY_JSON
[ "$DRY_RC" -ne 0 ] || fail 'a pin absent from the remote exited successfully'
[ "$(firstmate_status "$json")" = refused ] || fail 'a pin absent from the remote was not refused'
[ "$(firstmate_detail "$json")" = 'the exact pin is absent from the authoritative Firstmate main branch' ] \
  || fail "an absent pin was refused for the wrong reason: $(firstmate_detail "$json")"
pass 'a pin the authoritative remote does not carry is refused'

# ------------------------- an unreachable remote is unknown, never applyable

# Put the checkout back behind the pin so these cases reach the probe at all.
write_pins "$AHEAD_COMMIT"
"$REAL_GIT" -C "$CHECKOUT" reset -q --hard "$BASE_COMMIT"
[ "$(head_commit)" != "$AHEAD_COMMIT" ] || fail 'the fixture is still converged, so the probe would be skipped'
set +e
TEST_REPO="file://$TMP_ROOT/no-such-remote.git"; dry_run; json=$DRY_JSON; unset TEST_REPO
set -e
[ "$DRY_RC" -ne 0 ] || fail 'an unreachable remote exited successfully'
[ "$(firstmate_status "$json")" = unknown ] || fail 'an unreachable remote was not reported as unknown'
[ "$(firstmate_detail "$json")" = 'could not reach the authoritative Firstmate main branch' ] \
  || fail "an unreachable remote reported the wrong detail: $(firstmate_detail "$json")"
pass 'an unreachable remote is bounded unknown and exits non-zero'

# ------------------------- private state that cannot be created is unknown

BLOCKER="$TMP_ROOT/blocked-tmp"
: >"$BLOCKER"
set +e
TEST_TMPDIR="$BLOCKER/inner"; dry_run; json=$DRY_JSON; unset TEST_TMPDIR
set -e
[ "$DRY_RC" -ne 0 ] || fail 'unusable temporary state exited successfully'
[ "$(firstmate_status "$json")" = unknown ] || fail 'unusable temporary state was not reported as unknown'
[ "$(firstmate_detail "$json")" = 'could not create private temporary state for the dry-run check' ] \
  || fail "unusable temporary state reported the wrong detail: $(firstmate_detail "$json")"
[ "$(head_commit)" = "$BASE_COMMIT" ] || fail 'an unknown preview moved the checkout'
pass 'private temporary state that cannot be created is bounded unknown'

# ------------------------- private state that cannot be removed is unknown

STICKY="$TMP_ROOT/sticky-tmp"
mkdir -p "$STICKY"
if [ "$(id -u)" -eq 0 ]; then
  pass 'cleanup-failure reporting is not expressible as root; skipped'
else
  # The git stub makes the temp parent read-only once the probe is under way, so
  # the probe itself succeeds and only the removal of its state fails.
  set +e
  TEST_TMPDIR="$STICKY"; TEST_LOCK_TMPDIR="$STICKY"; dry_run; json=$DRY_JSON
  unset TEST_TMPDIR TEST_LOCK_TMPDIR
  set -e
  chmod 700 "$STICKY"
  [ "$DRY_RC" -ne 0 ] || fail 'a dry-run that could not clean up exited successfully'
  [ "$(firstmate_status "$json")" = unknown ] \
    || fail "a failed cleanup was not reported as unknown: $(firstmate_status "$json") - $(firstmate_detail "$json")"
  case "$(firstmate_detail "$json")" in
    'private temporary dry-run state could not be removed:'*) : ;;
    *) fail "a failed cleanup reported the wrong detail: $(firstmate_detail "$json")" ;;
  esac
  rm -rf "${STICKY:?}"/*
  pass 'private temporary state that cannot be removed is bounded unknown'
fi

printf '\nall dev-tools-apply-updates dry-run tests passed\n'
