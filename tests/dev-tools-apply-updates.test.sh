#!/usr/bin/env bash
# Hermetic behavior tests for exact guarded convergence. No live tool is touched.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLY="$ROOT/bin/dev-tools-apply-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-apply-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

SEED="$TMP_ROOT/seed"
REMOTE="$TMP_ROOT/origin.git"
CHECKOUT="$TMP_ROOT/firstmate"
mkdir -p "$SEED"
git -C "$SEED" init -q -b main
printf 'one\n' >"$SEED/version"
git -C "$SEED" add version
git -C "$SEED" commit -qm one
git clone -q --bare "$SEED" "$REMOTE"
git clone -q "file://$REMOTE" "$CHECKOUT"
printf 'two\n' >>"$SEED/version"
git -C "$SEED" commit -qam two
PINNED_HEAD=$(git -C "$SEED" rev-parse HEAD)
git -C "$SEED" push -q "file://$REMOTE" main

PINS="$TMP_ROOT/pins.sh"
cp "$ROOT/config/dev-tools-versions.sh" "$PINS"
printf '\nFIRSTMATE_REV=%s\n' "$PINNED_HEAD" >>"$PINS"
# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS"
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package version _integrity _guarded _channel <<<"$row"
  [ "$name" = quota-axi ] && QUOTA_AXI_VERSION=$version && QUOTA_COMMAND=$command_name
done
: "${QUOTA_AXI_VERSION:?quota-axi pin missing}"
: "${QUOTA_COMMAND:?quota-axi command missing}"
QUOTA_PRIOR=0.0.1

FAKEBIN="$TMP_ROOT/fakebin"
PREFIX="$TMP_ROOT/npm-prefix"
STATE="$TMP_ROOT/state"
mkdir -p "$FAKEBIN" "$PREFIX/bin" "$STATE"
RECEIPTS="$TMP_ROOT/receipts"
mkdir -p "$RECEIPTS"
NPM_LOG="$TMP_ROOT/npm.log"
CHECKER_LOG="$TMP_ROOT/checker.log"
LIFECYCLE_LOG="$TMP_ROOT/lifecycle.log"
: >"$NPM_LOG"; : >"$CHECKER_LOG"; : >"$LIFECYCLE_LOG"

cat >"$FAKEBIN/checker" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$TEST_CHECKER_LOG"
[ "${TEST_INVALID_CHECKER:-0}" = 1 ] && { printf '{}\n'; exit 0; }
# shellcheck source=/dev/null
source "$TEST_PINS"
tools=$(jq -cn --arg current "$(git -C "$TEST_FIRSTMATE" rev-parse HEAD)" --arg pin "$FIRSTMATE_REV" \
  '[{name:"firstmate",current:$current,pinned:$pin,latest_stable:$pin,status:(if $current==$pin then "up_to_date" else "drifted" end)}]')
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package pinned _integrity guarded _channel <<<"$row"
  [ "$guarded" = yes ] || continue
  # The installed version comes from the npm prefix, which is where the apply
  # tier writes and where a reversal would read it back from.
  current=unknown
  if [ -x "$TEST_PREFIX/bin/$command_name" ]; then
    current=$(timeout "${TEST_NETWORK_TIMEOUT:-15}" env NO_UPDATE_NOTIFIER=1 "$TEST_PREFIX/bin/$command_name" --version 2>&1 \
      | grep -Eo '[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z]+)?' | head -1)
  fi
  [ -n "$current" ] || current=unknown
  [ "$name" = quota-axi ] && [ -n "${TEST_QUOTA_CURRENT:-}" ] && current=$TEST_QUOTA_CURRENT
  latest=$pinned
  [ "$name" = quota-axi ] && [ -n "${TEST_STALE_CHECKER_LATEST:-}" ] && latest=$TEST_STALE_CHECKER_LATEST
  item=$(jq -cn --arg name "$name" --arg current "$current" --arg pinned "$pinned" --arg latest "$latest" \
    '{name:$name,current:$current,pinned:$pinned,latest_stable:$latest,status:(if $current==$pinned then "up_to_date" else "drifted" end)}')
  tools=$(jq -cn --argjson tools "$tools" --argjson item "$item" '$tools+[$item]')
done
# Hostile report-only entries prove that checker output cannot widen apply scope.
tools=$(jq -cn --argjson tools "$tools" '$tools + [
  {name:"codex",current:"0.1.0",pinned:"9.9.9",latest_stable:"9.9.9",status:"drifted"},
  {name:"herdr",current:"0.8.2",pinned:"0.9.0",latest_stable:"0.9.0",status:"drifted"},
  {name:"no-mistakes",current:"1.60.2",pinned:"1.72.0",latest_stable:"1.72.0",status:"drifted"}
]')
jq -cn --argjson tools "$tools" '{schema_version:4,tools:$tools}'
SH

cat >"$FAKEBIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$TEST_NPM_LOG"
# shellcheck source=/dev/null
source "$TEST_PINS"
# Simulates a worker lane starting inside the bounded re-verification window.
[ -n "${TEST_WORKER_APPEARS:-}" ] && printf 'lane\n' >"$TEST_WORKER_APPEARS"
if [ "$1" = view ]; then
  spec=$2
  package=${spec%@*}
  version=${spec##*@}
  for row in "${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r name _command_name candidate pinned integrity guarded _channel <<<"$row"
    [ "$guarded" = yes ] || continue
    [ "$candidate" = "$package" ] || continue
    if [ "$version" != "$pinned" ]; then
      # The installed prior version, published with its own integrity.
      jq -cn --arg v "$version" --arg i "sha512-prior-$version" '{version:$v,"dist.integrity":$i}'
      exit 0
    fi
    [ "$name" = "${TEST_BAD_PACKAGE:-}" ] && integrity=sha512-wrong
    jq -cn --arg v "$version" --arg i "$integrity" '{version:$v,"dist.integrity":$i}'
    exit 0
  done
  exit 1
fi
if [ "$1" = install ]; then
  spec=$3
  for row in "${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r _name command_name package pinned _integrity guarded _channel <<<"$row"
    [ "$guarded" = yes ] || continue
    [ "$spec" = "$package@$pinned" ] || continue
    mkdir -p "$NPM_CONFIG_PREFIX/bin"
    printf '#!/usr/bin/env bash\nprintf "%s %s\\n"\n' "$command_name" "$pinned" >"$NPM_CONFIG_PREFIX/bin/$command_name"
    chmod +x "$NPM_CONFIG_PREFIX/bin/$command_name"
    exit 0
  done
fi
exit 1
SH

cat >"$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
printf 'herdr %s\n' "$*" >>"$TEST_LIFECYCLE_LOG"
exit 99
SH
cat >"$FAKEBIN/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf 'no-mistakes %s\n' "$*" >>"$TEST_LIFECYCLE_LOG"
exit 99
SH
chmod +x "$FAKEBIN"/*

# Five packages begin current. quota-axi begins at an earlier installed version,
# so it is the single drifted package and its prior state is really in the prefix.
seed_prefix() { # command version
  printf '#!/usr/bin/env bash\nprintf "%s %s\\n"\n' "$1" "$2" >"$PREFIX/bin/$1"
  chmod +x "$PREFIX/bin/$1"
}
seed_quota_prior() { seed_prefix "$QUOTA_COMMAND" "$QUOTA_PRIOR"; }
quota_version() {
  [ -x "$PREFIX/bin/$QUOTA_COMMAND" ] || return 0
  env NO_UPDATE_NOTIFIER=1 "$PREFIX/bin/$QUOTA_COMMAND" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){1,3}' | head -1
}
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package pinned _integrity guarded _channel <<<"$row"
  [ "$guarded" = yes ] || continue
  [ "$name" = quota-axi ] && continue
  seed_prefix "$command_name" "$pinned"
done
seed_quota_prior

run_apply() {
  env HOME="$TMP_ROOT/home" PATH="$FAKEBIN:/usr/bin:/bin" DEV_TOOLS_PINS_FILE="$PINS" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$FAKEBIN/checker" DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" \
    DEV_TOOLS_FIRSTMATE_REPO="file://$REMOTE" \
    DEV_TOOLS_UPDATE_NPM_BIN="$FAKEBIN/npm" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" DEV_TOOLS_UPDATE_GIT_BIN="$(command -v git)" \
    TEST_PINS="$PINS" TEST_PREFIX="$PREFIX" TEST_FIRSTMATE="$CHECKOUT" TEST_NPM_LOG="$NPM_LOG" TEST_CHECKER_LOG="$CHECKER_LOG" \
    TEST_LIFECYCLE_LOG="$LIFECYCLE_LOG" TEST_BAD_PACKAGE="${TEST_BAD_PACKAGE:-}" TEST_INVALID_CHECKER="${TEST_INVALID_CHECKER:-0}" \
    TEST_STALE_CHECKER_LATEST="${TEST_STALE_CHECKER_LATEST:-}" TEST_WORKER_APPEARS="${TEST_WORKER_APPEARS:-}" \
    TEST_QUOTA_CURRENT="${TEST_QUOTA_CURRENT:-}" TEST_NETWORK_TIMEOUT="${TEST_NETWORK_TIMEOUT:-15}" \
    DEV_TOOLS_UPDATE_NETWORK_TIMEOUT_SECONDS="${TEST_NETWORK_TIMEOUT:-15}" \
    DEV_TOOLS_APPLY_RECEIPT_DIR="$RECEIPTS" \
    "$APPLY" "$@"
}

TEST_STALE_CHECKER_LATEST=9.9.9
json=$(run_apply --json)
unset TEST_STALE_CHECKER_LATEST
[ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$PINNED_HEAD" ] || fail 'Firstmate did not fast-forward to the exact recorded commit'
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = applied ] || fail 'Firstmate exact update was not reported applied'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = applied ] || fail 'quota-axi exact pin was not applied'
grep -Fq "view quota-axi@$QUOTA_AXI_VERSION version dist.integrity --json" "$NPM_LOG" || fail 'exact npm version and integrity were not re-verified'
grep -Fq "install -g quota-axi@$QUOTA_AXI_VERSION" "$NPM_LOG" || fail 'stale checker latest changed the exact install target'
! grep -Fq '@openai/codex' "$NPM_LOG" || fail 'checker widened the hard allowlist to Codex'
[ ! -s "$LIFECYCLE_LOG" ] || fail 'apply invoked Herdr or no-mistakes'
pass 'guarded apply independently verifies and converges only exact allowlisted pins'

: >"$NPM_LOG"
json=$(run_apply --json)
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = up_to_date ] || fail 'Firstmate rerun was not idempotent'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = up_to_date ] || fail 'npm rerun was not idempotent'
[ ! -s "$NPM_LOG" ] || fail 'idempotent rerun contacted npm'
pass 'converged rerun is idempotent'

PACKAGED_BIN="$TMP_ROOT/packaged/bin"
mkdir -p "$PACKAGED_BIN"
cp "$APPLY" "$PACKAGED_BIN/dev-tools-apply-updates"
ln -s checker "$FAKEBIN/dev-tools-check-updates"
: >"$CHECKER_LOG"
json=$(env HOME="$TMP_ROOT/home" PATH="$FAKEBIN:/usr/bin:/bin" DEV_TOOLS_PINS_FILE="$PINS" \
  DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" DEV_TOOLS_FIRSTMATE_REPO="file://$REMOTE" \
  DEV_TOOLS_UPDATE_NPM_BIN="$FAKEBIN/npm" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" DEV_TOOLS_UPDATE_GIT_BIN="$(command -v git)" \
  TEST_PINS="$PINS" TEST_PREFIX="$PREFIX" TEST_FIRSTMATE="$CHECKOUT" TEST_NPM_LOG="$NPM_LOG" TEST_CHECKER_LOG="$CHECKER_LOG" \
  TEST_LIFECYCLE_LOG="$LIFECYCLE_LOG" "$PACKAGED_BIN/dev-tools-apply-updates" --dry-run --json)
[ "$(printf '%s' "$json" | jq -r '.schema_version')" = 3 ] || fail 'packaged apply could not resolve the checker from PATH'
grep -Fq -- '--json --force --no-cache' "$CHECKER_LOG" || fail 'packaged apply did not invoke the PATH checker'
pass 'Nix-packaged apply resolves its checker runtime dependency'

seed_quota_prior
: >"$NPM_LOG"
json=$(run_apply --dry-run --json)
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = would_apply ] || fail 'dry-run did not preview exact convergence'
grep -Fq "view quota-axi@$QUOTA_AXI_VERSION version dist.integrity --json" "$NPM_LOG" || fail 'dry-run did not re-verify the exact artifact'
! grep -Fq 'install -g' "$NPM_LOG" || fail 'dry-run installed a package'
[ "$(quota_version)" = "$QUOTA_PRIOR" ] || fail 'dry-run changed the installed tool version'
pass 'dry-run re-verifies but performs no mutation'

# ---- the recorded prior comes from the npm prefix a reversal would write into

# Detection resolves through PATH, the reversal writes into $NPM_PREFIX. When the
# prefix carries nothing there is no prior state to reverse to, so the mutation is
# refused rather than recorded against a version reinstalling could not restore.
: >"$NPM_LOG"
rm -f "$PREFIX/bin/$QUOTA_COMMAND"
TEST_QUOTA_CURRENT=$QUOTA_PRIOR
set +e
json=$(run_apply --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a package absent from the npm prefix exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = refused ] \
  || fail 'a package absent from the npm prefix was not refused'
printf '%s' "$json" | jq -e '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail | test("carries no installed")' >/dev/null \
  || fail 'the refusal did not name the npm prefix as the missing prior state'
if grep -Fq 'install -g' "$NPM_LOG"; then fail 'a package with no reversible prior state was installed anyway'; fi
set +e
dry=$(run_apply --dry-run --json)
set -e
[ "$(printf '%s' "$dry" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = refused ] \
  || fail 'the preview promised a mutation the apply path refuses'
unset TEST_QUOTA_CURRENT
seed_quota_prior
pass 'a package the npm prefix does not carry is refused in both preview and apply'

# Detection and the prefix disagreeing means the receipt would record a prior the
# reversal would never restore, so that mutation is refused too.
: >"$NPM_LOG"
TEST_QUOTA_CURRENT=0.2.0
set +e
json=$(run_apply --json)
rc=$?
set -e
unset TEST_QUOTA_CURRENT
[ "$rc" -ne 0 ] || fail 'a detection and prefix disagreement exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = refused ] \
  || fail 'a detection and prefix disagreement was not refused'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .observed')" = "$QUOTA_PRIOR" ] \
  || fail 'the refusal did not report the version the npm prefix actually carries'
if grep -Fq 'install -g' "$NPM_LOG"; then fail 'a mutation ran while the prior state was ambiguous'; fi
[ "$(quota_version)" = "$QUOTA_PRIOR" ] || fail 'the refused package was changed anyway'
pass 'detection disagreeing with the npm prefix refuses the mutation'

# ---- one bounded version-observation contract, and labels that match the cause

# A tool that prints its banner on stderr is read the same way by detection and by
# the prefix observer, so it converges instead of being refused for a prior state
# that is plainly there.
: >"$NPM_LOG"
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "%s %s\\n" >&2\n' "$QUOTA_COMMAND" "$QUOTA_PRIOR"
} >"$PREFIX/bin/$QUOTA_COMMAND"
chmod +x "$PREFIX/bin/$QUOTA_COMMAND"
rm -f "$RECEIPTS"/*.json
set +e
json=$(run_apply --json)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "a stderr version banner blocked the apply: $(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')"
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = applied ] \
  || fail "a stderr version banner was not observed: $(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')"
set -- "$RECEIPTS"/*.json
[ -f "$1" ] || fail 'the converged apply wrote no receipt'
[ "$(jq -r '.tools[] | select(.name=="quota-axi") | .prior' "$1")" = "$QUOTA_PRIOR" ] \
  || fail 'the receipt did not record the version the prefix reported on stderr'
seed_quota_prior
pass 'the prefix observer reads a version the same way detection does'

# Present but unreadable is a different cause from absent, and the refusal says
# which one it was rather than claiming the prefix carries nothing.
: >"$NPM_LOG"
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "%s (unversioned build)\\n"\n' "$QUOTA_COMMAND"
} >"$PREFIX/bin/$QUOTA_COMMAND"
chmod +x "$PREFIX/bin/$QUOTA_COMMAND"
TEST_QUOTA_CURRENT=$QUOTA_PRIOR
set +e
json=$(run_apply --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'an unreadable installed version exited successfully'
detail=$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')
case "$detail" in
  *'reported no recognisable version'*) : ;;
  *) fail "an unreadable installed version was refused for the wrong reason: $detail" ;;
esac
if grep -Fq 'install -g' "$NPM_LOG"; then fail 'a package with an unreadable prior version was installed anyway'; fi

# A command that fails fast is not a hang, and the refusal reports the status it
# actually exited with instead of a bound that was never reached.
: >"$NPM_LOG"
{
  printf '#!/usr/bin/env bash\n'
  printf 'exit 126\n'
} >"$PREFIX/bin/$QUOTA_COMMAND"
chmod +x "$PREFIX/bin/$QUOTA_COMMAND"
set +e
json=$(run_apply --json)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'a failing installed command exited successfully'
detail=$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')
case "$detail" in
  *'exited 126 without reporting a version'*) : ;;
  *) fail "a failing installed command was refused for the wrong reason: $detail" ;;
esac
if grep -Fq 'install -g' "$NPM_LOG"; then fail 'a package whose prior version could not be read was installed anyway'; fi

# The observation is bounded, so a command that never answers cannot hang a run.
: >"$NPM_LOG"
{
  printf '#!/usr/bin/env bash\n'
  printf 'sleep 30\n'
  printf 'printf "%s %s\\n"\n' "$QUOTA_COMMAND" "$QUOTA_PRIOR"
} >"$PREFIX/bin/$QUOTA_COMMAND"
chmod +x "$PREFIX/bin/$QUOTA_COMMAND"
TEST_NETWORK_TIMEOUT=1
started=$SECONDS
set +e
json=$(run_apply --json)
rc=$?
set -e
elapsed=$((SECONDS - started))
unset TEST_NETWORK_TIMEOUT
unset TEST_QUOTA_CURRENT
[ "$rc" -ne 0 ] || fail 'an unresponsive installed command exited successfully'
detail=$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')
case "$detail" in
  *'did not answer within 1s'*) : ;;
  *) fail "an unresponsive installed command was refused for the wrong reason: $detail" ;;
esac
[ "$elapsed" -lt 20 ] || fail "the observation was not bounded: the run took ${elapsed}s"
if grep -Fq 'install -g' "$NPM_LOG"; then fail 'a package whose prior version could not be read was installed anyway'; fi
seed_quota_prior
pass 'an unreadable, failing, or unresponsive prefix command each gets its own reason, under a bound'

: >"$NPM_LOG"
TEST_BAD_PACKAGE=quota-axi
set +e
json=$(run_apply --json)
rc=$?
set -e
unset TEST_BAD_PACKAGE
[ "$rc" -ne 0 ] || fail 'registry integrity mismatch exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = refused ] || fail 'registry integrity mismatch was not refused'
! grep -Fq 'install -g' "$NPM_LOG" || fail 'refused artifact was installed'
pass 'independent exact-artifact mismatch fails closed'

: >"$NPM_LOG"
SAFE_PINS=$PINS
PINS="$TMP_ROOT/unsafe-pins.sh"
sed "s/|$QUOTA_AXI_VERSION|/|latest|/" "$SAFE_PINS" >"$PINS"
set +e
json=$(run_apply --json)
rc=$?
set -e
PINS=$SAFE_PINS
[ "$rc" -ne 0 ] || fail 'unsafe moving version string exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = refused ] || fail 'unsafe moving version string was not refused'
! grep -Fq 'view quota-axi@latest' "$NPM_LOG" || fail 'unsafe version reached the registry'
pass 'unsafe and moving version strings are refused before source access'

: >"$NPM_LOG"; : >"$CHECKER_LOG"
printf 'lane\n' >"$STATE/active.meta"
json=$(run_apply --json)
[ "$(printf '%s' "$json" | jq -r '.worker_guard.status')" = active ] || fail 'worker guard missed an active lane'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = deferred ] || fail 'active worker did not defer npm'
[ ! -s "$NPM_LOG" ] && [ ! -s "$CHECKER_LOG" ] || fail 'worker deferral still queried or mutated sources'
rm -f "$STATE/active.meta"
pass 'active Firstmate lanes defer every mutation before detection'

# A lane that only appears inside the re-verification window must be visible in
# the emitted guard, not just in the tier that deferred because of it.
: >"$NPM_LOG"; : >"$CHECKER_LOG"
seed_quota_prior
TEST_WORKER_APPEARS="$STATE/appeared.meta"
set +e
json=$(run_apply --json)
set -e
unset TEST_WORKER_APPEARS
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .detail')" = 'workers appeared during re-verification' ] \
  || fail 'a lane appearing during re-verification did not defer the mutation'
[ "$(quota_version)" = "$QUOTA_PRIOR" ] || fail 'a lane appearing during re-verification still installed the package'
[ "$(printf '%s' "$json" | jq -r '.worker_guard.status')" = active ] \
  || fail 'the result reported a clear worker guard while a tier deferred on an active lane'
[ "$(printf '%s' "$json" | jq -r '.worker_guard.in_flight')" = 1 ] || fail 'the result did not count the lane that deferred the mutation'
rm -f "$STATE/appeared.meta"
pass 'the emitted worker guard reflects lanes found by pre-mutation re-verification'

TEST_INVALID_CHECKER=1
set +e
json=$(run_apply --json)
rc=$?
set -e
unset TEST_INVALID_CHECKER
[ "$rc" -ne 0 ] || fail 'unknown checker source exited successfully'
[ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = refused ] || fail 'unknown checker source was not refused'
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = refused ] || fail 'unknown checker source did not refuse npm'
pass 'unknown detection source refuses every mutation'

[ ! -s "$LIFECYCLE_LOG" ] || fail 'Herdr or no-mistakes lifecycle command was ever invoked'
help=$($APPLY --help)
case "$help" in *'MUST NEVER install, update, invoke, reload, stop, or restart'*) : ;; *) fail 'operator contract omits the runtime-hosting safety boundary' ;; esac
pass 'Herdr and the shared no-mistakes daemon are absent from apply behavior'

PACKAGED_APPLY="$TMP_ROOT/packaged-dev-tools-apply-updates"
{
  printf '#!/usr/bin/env bash\n'
  printf 'export DEV_TOOLS_PINS_FILE=/nix/store/aaaaaaaa-dev-tools-versions.sh\n'
  cat "$APPLY"
} >"$PACKAGED_APPLY"
chmod +x "$PACKAGED_APPLY"
packaged_help=$("$PACKAGED_APPLY" --help)
[ "$(printf '%s\n' "$packaged_help" | head -1)" = "$(printf '%s\n' "$help" | head -1)" ] || fail 'the packaged --help does not start with the usage header'
if printf '%s\n' "$packaged_help" | grep -Eq '/nix/store/|env bash'; then
  fail 'the packaged --help leaks wrapper exports or the interpreter line'
fi
case "$packaged_help" in *'MUST NEVER install, update, invoke, reload, stop, or restart'*) : ;; *) fail 'the packaged --help omits the runtime-hosting safety boundary' ;; esac
pass 'the packaged --help prints only the operator contract'

# `tests/*.test.sh` is this repository's only test-discovery convention - there is
# no runner script - so every match has to be directly invocable. A suite that
# lost its executable bit is skipped or dies with exit 126 while the rest pass.
for suite in "$ROOT"/tests/*.test.sh; do
  [ -x "$suite" ] || fail "$(basename "$suite") is not directly executable, so tests/*.test.sh discovery cannot run it"
done
pass 'every test suite in tests/ can be invoked directly'

printf '\nall dev-tools-apply-updates tests passed\n'
