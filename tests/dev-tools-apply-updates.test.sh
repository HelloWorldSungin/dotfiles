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
  IFS='|' read -r name _command _package version _integrity _guarded _channel <<<"$row"
  [ "$name" = quota-axi ] && QUOTA_AXI_VERSION=$version
done
: "${QUOTA_AXI_VERSION:?quota-axi pin missing}"

FAKEBIN="$TMP_ROOT/fakebin"
PREFIX="$TMP_ROOT/npm-prefix"
STATE="$TMP_ROOT/state"
mkdir -p "$FAKEBIN" "$PREFIX/bin" "$STATE"
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
  current=$pinned
  if [ "$name" = quota-axi ] && [ ! -x "$TEST_PREFIX/bin/$command_name" ]; then current=0.0.1; fi
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
  {name:"no-mistakes",current:"1.60.2",pinned:"1.70.1",latest_stable:"1.70.1",status:"drifted"}
]')
jq -cn --argjson tools "$tools" '{schema_version:4,tools:$tools}'
SH

cat >"$FAKEBIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$TEST_NPM_LOG"
# shellcheck source=/dev/null
source "$TEST_PINS"
if [ "$1" = view ]; then
  spec=$2
  for row in "${NPM_TOOL_PINS[@]}"; do
    IFS='|' read -r name command_name package pinned integrity guarded _channel <<<"$row"
    [ "$guarded" = yes ] || continue
    [ "$spec" = "$package@$pinned" ] || continue
    [ "$name" = "${TEST_BAD_PACKAGE:-}" ] && integrity=sha512-wrong
    jq -cn --arg v "$pinned" --arg i "$integrity" '{version:$v,"dist.integrity":$i}'
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

# Five packages begin current. quota-axi is the single drifted package.
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r name command_name _package pinned _integrity guarded _channel <<<"$row"
  [ "$guarded" = yes ] || continue
  [ "$name" = quota-axi ] && continue
  printf '#!/usr/bin/env bash\nprintf "%s %s\\n"\n' "$command_name" "$pinned" >"$PREFIX/bin/$command_name"
  chmod +x "$PREFIX/bin/$command_name"
done

run_apply() {
  env HOME="$TMP_ROOT/home" PATH="$FAKEBIN:/usr/bin:/bin" DEV_TOOLS_PINS_FILE="$PINS" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$FAKEBIN/checker" DEV_TOOLS_FIRSTMATE_PATH="$CHECKOUT" DEV_TOOLS_FIRSTMATE_STATE_DIR="$STATE" \
    DEV_TOOLS_FIRSTMATE_REPO="file://$REMOTE" \
    DEV_TOOLS_UPDATE_NPM_BIN="$FAKEBIN/npm" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" DEV_TOOLS_UPDATE_GIT_BIN="$(command -v git)" \
    TEST_PINS="$PINS" TEST_PREFIX="$PREFIX" TEST_FIRSTMATE="$CHECKOUT" TEST_NPM_LOG="$NPM_LOG" TEST_CHECKER_LOG="$CHECKER_LOG" \
    TEST_LIFECYCLE_LOG="$LIFECYCLE_LOG" TEST_BAD_PACKAGE="${TEST_BAD_PACKAGE:-}" TEST_INVALID_CHECKER="${TEST_INVALID_CHECKER:-0}" \
    TEST_STALE_CHECKER_LATEST="${TEST_STALE_CHECKER_LATEST:-}" "$APPLY" "$@"
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
[ "$(printf '%s' "$json" | jq -r '.schema_version')" = 2 ] || fail 'packaged apply could not resolve the checker from PATH'
grep -Fq -- '--json --force --no-cache' "$CHECKER_LOG" || fail 'packaged apply did not invoke the PATH checker'
pass 'Nix-packaged apply resolves its checker runtime dependency'

rm -f "$PREFIX/bin/quota-axi"
: >"$NPM_LOG"
json=$(run_apply --dry-run --json)
[ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name=="quota-axi") | .status')" = would_apply ] || fail 'dry-run did not preview exact convergence'
grep -Fq "view quota-axi@$QUOTA_AXI_VERSION version dist.integrity --json" "$NPM_LOG" || fail 'dry-run did not re-verify the exact artifact'
! grep -Fq 'install -g' "$NPM_LOG" || fail 'dry-run installed a package'
[ ! -e "$PREFIX/bin/quota-axi" ] || fail 'dry-run created the tool command'
pass 'dry-run re-verifies but performs no mutation'

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

printf '\nall dev-tools-apply-updates tests passed\n'
