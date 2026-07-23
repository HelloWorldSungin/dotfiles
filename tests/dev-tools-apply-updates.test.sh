#!/usr/bin/env bash
# Self-contained behavior tests for bin/dev-tools-apply-updates.
#
# The firstmate fast-forward runs against a real local file:// repository so the
# ff merge actually happens and is observable. Detection is served by an injected
# fake dev-tools-check-updates, and npm is an injected recorder. The worker guard
# reads an injected state directory. No test contacts the network.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLY="$ROOT/bin/dev-tools-apply-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-apply-updates-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3" ;;
    *) ;;
  esac
}

# Build a checkout on branch trunk sitting one commit behind origin/trunk, so a
# fast-forward is available and observable.
make_git_world() {
  local name=$1 base seed remote checkout
  base="$TMP_ROOT/$name"
  seed="$base/seed"
  remote="$base/origin.git"
  checkout="$base/checkout"
  mkdir -p "$seed"
  git -C "$seed" init -q -b trunk
  printf 'one\n' > "$seed/version.txt"
  git -C "$seed" add version.txt
  git -C "$seed" commit -qm one
  git clone -q --bare "$seed" "$remote"
  git clone -q "file://$remote" "$checkout"
  printf 'two\n' >> "$seed/version.txt"
  git -C "$seed" commit -qam two
  git -C "$seed" push -q "file://$remote" trunk
  printf '%s\n' "$checkout"
}

make_fixture_tools() {
  local base=$1 fakebin="$1/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/npm-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_NPM_LOG"
if [ "${3:-}" = view ]; then
  name=${4%@latest}
  latest=$(jq -r --arg name "$name" '.[$name] // empty' "$TEST_NPM_LATEST_JSON")
  [ -n "$latest" ] || exit 1
  jq -cn --arg latest "$latest" '$latest'
  exit 0
fi
if [ -n "${TEST_CREATE_LANE_AFTER_NPM_INSTALL:-}" ] && [ ! -e "$TEST_CREATE_LANE_AFTER_NPM_INSTALL" ]; then
  printf 'worktree=/somewhere\n' > "$TEST_CREATE_LANE_AFTER_NPM_INSTALL"
fi
exit "${TEST_NPM_RC:-0}"
SH
  cat > "$fakebin/checker-fixture" <<'SH'
#!/usr/bin/env bash
# Ignores --json/--force; emits the prepared detection object.
if [ -n "${TEST_CREATE_LANE_DURING_DETECTION:-}" ]; then
  printf 'worktree=/somewhere\n' > "$TEST_CREATE_LANE_DURING_DETECTION"
fi
cat "$FAKE_CHECKER_JSON"
SH
  chmod +x "$fakebin"/*
  printf '%s\n' "$fakebin"
}

# Emit a checker detection JSON. Args:
#   $1 firstmate status (update_available|up_to_date|unknown)
#   $2 firstmate default branch
#   $3 firstmate behind
#   $4 npm status (update_available|up_to_date|unknown)
#   $5 npm packages JSON array
write_detection() {
  jq -cn \
    --arg fm_status "$1" --arg branch "$2" --argjson behind "$3" \
    --arg npm_status "$4" --argjson packages "$5" '
    {schema_version:1,
     sources:{
       firstmate:{status:$fm_status,default_branch:$branch,behind:$behind},
       npm_global:{status:$npm_status,packages:$packages},
       treehouse:{status:"up_to_date"},
       no_mistakes:{status:"up_to_date"},
       nix_pinned:{status:"excluded"}}}' > "$FAKE_CHECKER_JSON"
  jq '.sources.npm_global.packages | map({key:.name,value:.latest}) | from_entries' \
    "$FAKE_CHECKER_JSON" > "$TEST_NPM_LATEST_JSON"
}

run_apply() {
  env \
    HOME="$TEST_HOME" \
    DEV_TOOLS_FIRSTMATE_PATH="$TEST_REPO" \
    DEV_TOOLS_FIRSTMATE_STATE_DIR="$TEST_STATE_DIR" \
    DEV_TOOLS_APPLY_CHECKER_BIN="$TEST_FAKEBIN/checker-fixture" \
    DEV_TOOLS_UPDATE_GIT_BIN="$(command -v git)" \
    DEV_TOOLS_UPDATE_NPM_BIN="$TEST_FAKEBIN/npm-fixture" \
    DEV_TOOLS_UPDATE_NPM_PREFIX="$TEST_NPM_PREFIX" \
    "$APPLY" "$@"
}

configure_fixture() {
  local base=$1
  TEST_HOME="$base/home"
  TEST_STATE_DIR="$base/state"
  TEST_NPM_PREFIX="$base/npm-prefix"
  TEST_FAKEBIN=$(make_fixture_tools "$base")
  mkdir -p "$TEST_HOME" "$TEST_STATE_DIR" "$TEST_NPM_PREFIX"
  FAKE_CHECKER_JSON="$base/detection.json"
  TEST_NPM_LOG="$base/npm.log"
  TEST_NPM_LATEST_JSON="$base/npm-latest.json"
  : > "$TEST_NPM_LOG"
  printf '{}\n' > "$TEST_NPM_LATEST_JSON"
  TEST_NPM_RC=0
  TEST_CREATE_LANE_DURING_DETECTION=
  TEST_CREATE_LANE_AFTER_NPM_INSTALL=
  export FAKE_CHECKER_JSON TEST_NPM_LOG TEST_NPM_LATEST_JSON TEST_NPM_RC
  export TEST_CREATE_LANE_DURING_DETECTION TEST_CREATE_LANE_AFTER_NPM_INSTALL
}

git_head() {
  git -C "$TEST_REPO" rev-parse HEAD
}

test_safe_tier_apply() {
  local base json human before after
  base="$TMP_ROOT/apply"
  TEST_REPO=$(make_git_world apply-git)
  configure_fixture "$base"
  write_detection update_available trunk 1 update_available \
    '[{"name":"quota-axi","current":"0.1.6","latest":"0.1.9"}]'
  before=$(git_head)

  json=$(run_apply --json) || fail "apply returned non-zero on a clean safe update"
  [ "$(printf '%s' "$json" | jq -r '.worker_guard.status')" = clear ] \
    || fail "worker guard was not clear with no lanes present"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = applied ] \
    || fail "firstmate fast-forward was not applied"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.behind')" = 1 ] \
    || fail "firstmate behind count was not reported"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = applied ] \
    || fail "npm tier was not applied"
  after=$(git_head)
  [ "$before" != "$after" ] || fail "firstmate HEAD did not advance after apply"
  [ "$(git -C "$TEST_REPO" rev-list --count HEAD..refs/remotes/origin/trunk)" -eq 0 ] \
    || fail "firstmate HEAD is not at origin/trunk after fast-forward"
  assert_contains "$(cat "$TEST_NPM_LOG")" "install -g quota-axi@0.1.9" "npm install command was not the pinned latest"

  human=$(run_apply)
  assert_contains "$human" "firstmate: up_to_date" "second human run was not idempotent for firstmate"
  pass "safe tiers apply the firstmate fast-forward and allowlisted npm install"
}

test_allowlist_is_never_widened() {
  local base json
  base="$TMP_ROOT/allowlist"
  TEST_REPO=$(make_git_world allowlist-git)
  configure_fixture "$base"
  # Checker output naming a non-allowlisted package must never be installed.
  write_detection up_to_date trunk 0 update_available \
    '[{"name":"quota-axi","current":"0.1.6","latest":"0.1.9"},{"name":"@openai/codex","current":"1.0.0","latest":"2.0.0"}]'

  json=$(run_apply --json) || fail "apply returned non-zero"
  [ "$(printf '%s' "$json" | jq '.tiers.npm_global.packages | length')" -eq 1 ] \
    || fail "a non-allowlisted package leaked into the applied set"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[0].name')" = quota-axi ] \
    || fail "the allowlisted package was not the one applied"
  assert_not_contains "$(cat "$TEST_NPM_LOG")" "codex" "a non-allowlisted package was installed"
  pass "npm apply is confined to the allowlist and never widens it"
}

test_npm_latest_is_reverified_before_install() {
  local base json npm_log
  base="$TMP_ROOT/npm-reverify"
  TEST_REPO=$(make_git_world npm-reverify-git)
  configure_fixture "$base"
  write_detection up_to_date trunk 0 update_available \
    '[{"name":"quota-axi","current":"1.0.0","latest":"1.1.0"}]'
  printf '{"quota-axi":"1.2.0"}\n' > "$TEST_NPM_LATEST_JSON"

  json=$(run_apply --json) || fail "npm source re-verification returned non-zero"
  npm_log=$(cat "$TEST_NPM_LOG")
  assert_contains "$npm_log" "view quota-axi@latest version --json" \
    "npm latest was not re-verified against the registry"
  assert_contains "$npm_log" "install -g quota-axi@1.2.0" \
    "npm did not install the re-verified latest version"
  assert_not_contains "$npm_log" "install -g quota-axi@1.1.0" \
    "npm installed the stale checker-reported version"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[0].latest')" = 1.2.0 ] \
    || fail "npm result did not report the re-verified latest version"
  pass "npm latest is re-verified against the registry before install"
}

test_unsafe_npm_versions_are_skipped() {
  local base json npm_log
  base="$TMP_ROOT/unsafe-versions"
  TEST_REPO=$(make_git_world unsafe-versions-git)
  configure_fixture "$base"
  write_detection up_to_date trunk 0 update_available \
    '[{"name":"chrome-devtools-axi","current":"1.0.0"},{"name":"gh-axi","current":"1.0.0","latest":"latest"},{"name":"gnhf","current":"1.0.0","latest":"1.2.3@npm:other"},{"name":"lavish-axi","current":"1.0.0","latest":"scope/pkg"},{"name":"quota-axi","current":"1.0.0","latest":"v1.2.3-beta.1"}]'

  json=$(run_apply --json) || fail "unsafe npm version specs returned non-zero"
  [ "$(printf '%s' "$json" | jq '[.tiers.npm_global.packages[] | select(.status == "skipped" and .detail == "unsafe version spec")] | length')" -eq 4 ] \
    || fail "unsafe npm version specs were not all recorded as skipped"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[] | select(.name == "quota-axi") | .status')" = applied ] \
    || fail "a valid concrete npm version was not applied"
  npm_log=$(cat "$TEST_NPM_LOG")
  assert_contains "$npm_log" "install -g quota-axi@v1.2.3-beta.1" \
    "the valid concrete npm version was not pinned"
  assert_not_contains "$npm_log" "chrome-devtools-axi" "a missing npm version was installed"
  assert_not_contains "$npm_log" "gh-axi" "the npm latest tag was installed"
  assert_not_contains "$npm_log" "gnhf" "an npm alias version spec was installed"
  assert_not_contains "$npm_log" "lavish-axi" "an npm path version spec was installed"
  pass "npm apply skips every unsafe version spec and continues safely"
}

test_worker_active_defers() {
  local base json human before after
  base="$TMP_ROOT/deferred"
  TEST_REPO=$(make_git_world deferred-git)
  configure_fixture "$base"
  write_detection update_available trunk 1 update_available \
    '[{"name":"quota-axi","current":"0.1.6","latest":"0.1.9"}]'
  # An in-flight worker lane: one state/<id>.meta file.
  printf 'worktree=/somewhere\n' > "$TEST_STATE_DIR/some-lane.meta"
  before=$(git_head)

  json=$(run_apply --json) || fail "deferral returned non-zero (should be a clean non-destructive exit)"
  [ "$(printf '%s' "$json" | jq -r '.worker_guard.status')" = active ] \
    || fail "worker guard did not detect the in-flight lane"
  [ "$(printf '%s' "$json" | jq -r '.worker_guard.in_flight')" = 1 ] \
    || fail "in-flight lane count was not reported"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = deferred ] \
    || fail "firstmate tier was not deferred while a worker was active"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = deferred ] \
    || fail "npm tier was not deferred while a worker was active"
  after=$(git_head)
  [ "$before" = "$after" ] || fail "deferral still moved firstmate HEAD"
  [ ! -s "$TEST_NPM_LOG" ] || fail "deferral still ran an npm install"
  human=$(run_apply)
  assert_contains "$human" "worker guard: active" "human deferral did not report active workers"
  assert_contains "$human" "firstmate: deferred" "human deferral did not defer firstmate"
  pass "an active worker defers every tier without mutating anything"
}

test_late_worker_defers_pending_mutations() {
  local base json before after
  base="$TMP_ROOT/late-before-merge"
  TEST_REPO=$(make_git_world late-before-merge-git)
  configure_fixture "$base"
  write_detection update_available trunk 1 up_to_date '[]'
  TEST_CREATE_LANE_DURING_DETECTION="$TEST_STATE_DIR/late.meta"
  export TEST_CREATE_LANE_DURING_DETECTION
  before=$(git_head)

  json=$(run_apply --json) || fail "late worker before merge returned non-zero"
  [ "$(printf '%s' "$json" | jq -r '.worker_guard.status')" = clear ] \
    || fail "the up-front worker guard did not run before detection"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = deferred ] \
    || fail "a worker appearing before merge did not defer firstmate"
  assert_contains "$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')" "workers active" \
    "late firstmate deferral did not explain the active worker"
  after=$(git_head)
  [ "$before" = "$after" ] || fail "firstmate merged after a late worker appeared"

  base="$TMP_ROOT/late-between-installs"
  TEST_REPO=$(make_git_world late-between-installs-git)
  configure_fixture "$base"
  write_detection up_to_date trunk 0 update_available \
    '[{"name":"chrome-devtools-axi","current":"1.0.0","latest":"1.1.0"},{"name":"gh-axi","current":"1.0.0","latest":"1.1.0"},{"name":"tasks-axi","current":"1.0.0","latest":"1.1.0"}]'
  TEST_CREATE_LANE_AFTER_NPM_INSTALL="$TEST_STATE_DIR/late.meta"
  export TEST_CREATE_LANE_AFTER_NPM_INSTALL

  json=$(run_apply --json) || fail "late worker between npm installs returned non-zero"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.status')" = deferred ] \
    || fail "late worker did not defer the npm tier"
  [ "$(printf '%s' "$json" | jq '[.tiers.npm_global.packages[] | select(.status == "applied")] | length')" -eq 1 ] \
    || fail "npm did not preserve the one install completed before the worker appeared"
  [ "$(printf '%s' "$json" | jq '[.tiers.npm_global.packages[] | select(.status == "deferred" and .detail == "workers active")] | length')" -eq 2 ] \
    || fail "npm did not defer every install pending after the worker appeared"
  [ "$(grep -c ' install -g ' "$TEST_NPM_LOG")" -eq 1 ] \
    || fail "npm continued installing after the worker appeared"
  pass "workers appearing after detection defer every pending mutation"
}

test_dry_run_applies_nothing() {
  local base json before after before_ref after_ref seed
  base="$TMP_ROOT/dryrun"
  TEST_REPO=$(make_git_world dryrun-git)
  configure_fixture "$base"
  git -C "$TEST_REPO" fetch -q origin trunk
  before_ref=$(git -C "$TEST_REPO" rev-parse refs/remotes/origin/trunk)
  seed="$TMP_ROOT/dryrun-git/seed"
  printf 'three\n' >> "$seed/version.txt"
  git -C "$seed" commit -qam three
  git -C "$seed" push -q "file://$TMP_ROOT/dryrun-git/origin.git" trunk
  write_detection update_available trunk 1 update_available \
    '[{"name":"gh-axi","current":"1.0.0","latest":"1.1.0"}]'
  before=$(git_head)

  json=$(run_apply --dry-run --json) || fail "dry-run returned non-zero"
  [ "$(printf '%s' "$json" | jq -r '.dry_run')" = true ] \
    || fail "dry-run flag was not reflected in output"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = would_apply ] \
    || fail "dry-run did not preview the firstmate fast-forward"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.behind')" = 1 ] \
    || fail "dry-run did not report the firstmate behind count"
  [ "$(printf '%s' "$json" | jq -r '.tiers.npm_global.packages[0].status')" = would_apply ] \
    || fail "dry-run did not preview the npm install"
  after=$(git_head)
  after_ref=$(git -C "$TEST_REPO" rev-parse refs/remotes/origin/trunk)
  [ "$before" = "$after" ] || fail "dry-run moved firstmate HEAD"
  [ "$before_ref" = "$after_ref" ] || fail "dry-run fetched and moved the origin tracking ref"
  [ ! -s "$TEST_NPM_LOG" ] || fail "dry-run ran an npm install"
  assert_contains "$(run_apply --dry-run)" "[dry-run]" "human dry-run lost its prefix"
  pass "dry-run previews both tiers without apply-side writes"
}

test_idempotent_rerun() {
  local base first second calls_after
  base="$TMP_ROOT/idempotent"
  TEST_REPO=$(make_git_world idempotent-git)
  configure_fixture "$base"
  write_detection update_available trunk 1 update_available \
    '[{"name":"tasks-axi","current":"0.2.0","latest":"0.3.0"}]'

  first=$(run_apply --json) || fail "first apply returned non-zero"
  [ "$(printf '%s' "$first" | jq -r '.tiers.firstmate.status')" = applied ] \
    || fail "first apply did not fast-forward"
  # Now current: firstmate is at origin (its own git check proves this regardless
  # of detection), and the checker reports npm up to date.
  write_detection up_to_date trunk 0 up_to_date '[]'
  : > "$TEST_NPM_LOG"

  second=$(run_apply --json) || fail "idempotent re-run returned non-zero"
  [ "$(printf '%s' "$second" | jq -r '.tiers.firstmate.status')" = up_to_date ] \
    || fail "re-run did not report firstmate up to date"
  [ "$(printf '%s' "$second" | jq -r '.tiers.npm_global.status')" = up_to_date ] \
    || fail "re-run did not report npm up to date"
  [ ! -s "$TEST_NPM_LOG" ] || fail "idempotent re-run still ran an npm install"
  pass "re-running when already current is a clean no-op"
}

test_firstmate_skips_when_not_ff() {
  local base json off_default
  base="$TMP_ROOT/notff"
  TEST_REPO=$(make_git_world notff-git)
  configure_fixture "$base"
  # Diverge HEAD so origin/trunk is no longer a clean fast-forward.
  git -C "$TEST_REPO" checkout -q -b trunk 2>/dev/null || git -C "$TEST_REPO" checkout -q trunk
  printf 'local-divergence\n' >> "$TEST_REPO/version.txt"
  git -C "$TEST_REPO" commit -qam divergent
  write_detection update_available trunk 1 up_to_date '[]'

  json=$(run_apply --json) || fail "non-ff case returned non-zero (should skip cleanly)"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = skipped ] \
    || fail "a non-fast-forward firstmate update was not skipped"
  assert_contains "$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')" "not a clean fast-forward" \
    "skip reason for non-ff was not explained"

  # And a detached HEAD is also skipped, never forced.
  git -C "$TEST_REPO" checkout -q --detach
  off_default=$(run_apply --json)
  [ "$(printf '%s' "$off_default" | jq -r '.tiers.firstmate.status')" = skipped ] \
    || fail "detached HEAD was not skipped"
  pass "firstmate refuses anything that is not a clean fast-forward on the default branch"
}

test_firstmate_reverifies_remote_default_branch() {
  local base json before after seed remote
  base="$TMP_ROOT/default-branch-changed"
  TEST_REPO=$(make_git_world default-branch-changed-git)
  configure_fixture "$base"
  write_detection update_available trunk 1 up_to_date '[]'
  seed="$TMP_ROOT/default-branch-changed-git/seed"
  remote="$TMP_ROOT/default-branch-changed-git/origin.git"
  git -C "$seed" branch main
  git -C "$seed" push -q "file://$remote" main
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  before=$(git_head)

  json=$(run_apply --json) || fail "changed remote default returned non-zero"
  [ "$(printf '%s' "$json" | jq -r '.tiers.firstmate.status')" = skipped ] \
    || fail "firstmate applied the checker-reported branch after the remote default changed"
  assert_contains "$(printf '%s' "$json" | jq -r '.tiers.firstmate.detail')" "origin default branch" \
    "changed remote default skip reason was not explained"
  after=$(git_head)
  [ "$before" = "$after" ] || fail "firstmate moved HEAD on a branch that is no longer the remote default"
  pass "firstmate re-verifies the remote default branch before applying"
}

test_packaged_help_starts_with_description() {
  local base packaged first
  base="$TMP_ROOT/packaged-help"
  packaged="$base/dev-tools-apply-updates"
  mkdir -p "$base"
  {
    printf '#!/usr/bin/env bash\n'
    cat "$APPLY"
  } > "$packaged"
  chmod +x "$packaged"

  first=$("$packaged" --help | sed -n '1p')
  [ "$first" = "dev-tools-apply-updates - guarded, opt-in auto-apply for the safe update tiers." ] \
    || fail "packaged help started with '$first'"
  pass "packaged help starts with the command description"
}

export GIT_AUTHOR_NAME=dev-tools-test
export GIT_AUTHOR_EMAIL=dev-tools-test@example.invalid
export GIT_COMMITTER_NAME=dev-tools-test
export GIT_COMMITTER_EMAIL=dev-tools-test@example.invalid
test_safe_tier_apply
test_allowlist_is_never_widened
test_npm_latest_is_reverified_before_install
test_unsafe_npm_versions_are_skipped
test_worker_active_defers
test_late_worker_defers_pending_mutations
test_dry_run_applies_nothing
test_idempotent_rerun
test_firstmate_skips_when_not_ff
test_firstmate_reverifies_remote_default_branch
test_packaged_help_starts_with_description
