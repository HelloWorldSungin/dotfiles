#!/usr/bin/env bash
# Self-contained behavior tests for bin/dev-tools-check-updates.
#
# Every publication source is deterministic. Firstmate fetches from a local
# file:// bare repository, while npm, curl, treehouse, and no-mistakes are
# injected executables. The health check receives a fake environment reader.
# No test contacts the network or depends on the real login environment.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHECKER="$ROOT/bin/dev-tools-check-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-check-updates-tests.XXXXXX")
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
  mkdir -p "$fakebin" "$base/npm-prefix" "$base/home/npm-prefix"
  cat > "$fakebin/npm-fixture" <<'SH'
#!/usr/bin/env bash
printf 'npm\n' >> "$TEST_FAKE_CALL_LOG"
cat "$TEST_FAKE_NPM_JSON"
exit "${TEST_FAKE_NPM_RC:-1}"
SH
  cat > "$fakebin/curl-fixture" <<'SH'
#!/usr/bin/env bash
printf 'curl\n' >> "$TEST_FAKE_CALL_LOG"
[ "${TEST_FAKE_CURL_FAIL:-0}" = 0 ] || exit 22
last=${!#}
case "$last" in
  *treehouse*) cat "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" ;;
  *no-mistakes*) cat "$TEST_FAKE_NO_MISTAKES_RELEASE_JSON" ;;
  *) exit 22 ;;
esac
SH
  cat > "$fakebin/treehouse-fixture" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] || exit 2
printf '%s\n' "${TEST_FAKE_TREEHOUSE_VERSION:-v2.0.0}"
SH
  cat > "$fakebin/no-mistakes-fixture" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] || exit 2
printf '%s\n' "${TEST_FAKE_NO_MISTAKES_VERSION:-no-mistakes version v1.40.0 (fake)}"
SH
  cat > "$fakebin/printenv-fixture" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = CHROME_DEVTOOLS_AXI_CHROME_ARGS ] || exit 2
rc=${TEST_FAKE_PRINTENV_RC:-0}
[ "$rc" -eq 0 ] || exit "$rc"
printf '%s\n' "${TEST_FAKE_CHROME_ARGS:-}"
SH
  chmod +x "$fakebin"/*
  printf '%s\n' "$fakebin"
}

write_release() {
  local path=$1 version=$2
  printf '{"tag_name":"%s"}\n' "$version" > "$path"
}

run_checker() {
  local now=$1
  shift
  env \
    HOME="$TEST_HOME" \
    DEV_TOOLS_FIRSTMATE_PATH="$TEST_REPO" \
    DEV_TOOLS_UPDATE_CACHE_PATH="$TEST_HOME/cache.json" \
    DEV_TOOLS_UPDATE_NOW_EPOCH="$now" \
    DEV_TOOLS_UPDATE_CACHE_TTL_SECONDS="${TEST_TTL:-14400}" \
    DEV_TOOLS_UPDATE_GIT_BIN="$(command -v git)" \
    DEV_TOOLS_UPDATE_NPM_BIN="$TEST_FAKEBIN/npm-fixture" \
    DEV_TOOLS_UPDATE_NPM_PREFIX="$TEST_HOME/npm-prefix" \
    DEV_TOOLS_UPDATE_CURL_BIN="$TEST_FAKEBIN/curl-fixture" \
    DEV_TOOLS_UPDATE_TREEHOUSE_BIN="$TEST_FAKEBIN/treehouse-fixture" \
    DEV_TOOLS_UPDATE_NO_MISTAKES_BIN="$TEST_FAKEBIN/no-mistakes-fixture" \
    DEV_TOOLS_HEALTH_PRINTENV_BIN="$TEST_FAKEBIN/printenv-fixture" \
    "$CHECKER" "$@"
}

configure_fixture() {
  local base=$1
  TEST_HOME="$base/home"
  TEST_FAKEBIN=$(make_fixture_tools "$base")
  mkdir -p "$TEST_HOME"
  TEST_FAKE_CALL_LOG="$base/calls.log"
  TEST_FAKE_NPM_JSON="$base/npm.json"
  TEST_FAKE_TREEHOUSE_RELEASE_JSON="$base/treehouse.json"
  TEST_FAKE_NO_MISTAKES_RELEASE_JSON="$base/no-mistakes.json"
  TEST_FAKE_NPM_RC=1
  TEST_FAKE_CURL_FAIL=0
  TEST_FAKE_TREEHOUSE_VERSION=v2.0.0
  TEST_FAKE_NO_MISTAKES_VERSION='no-mistakes version v1.40.0 (fake)'
  TEST_FAKE_PRINTENV_RC=0
  TEST_FAKE_CHROME_ARGS='--no-sandbox --disable-dev-shm-usage --disable-gpu'
  export TEST_FAKE_CALL_LOG TEST_FAKE_NPM_JSON TEST_FAKE_TREEHOUSE_RELEASE_JSON
  export TEST_FAKE_NO_MISTAKES_RELEASE_JSON TEST_FAKE_NPM_RC TEST_FAKE_CURL_FAIL
  export TEST_FAKE_TREEHOUSE_VERSION TEST_FAKE_NO_MISTAKES_VERSION
  export TEST_FAKE_PRINTENV_RC TEST_FAKE_CHROME_ARGS
}

test_source_parsing_and_summaries() {
  local base json human startup calls_before calls_after
  base="$TMP_ROOT/parsing"
  TEST_REPO=$(make_git_world parsing-git)
  configure_fixture "$base"
  cat > "$TEST_FAKE_NPM_JSON" <<'JSON'
{
  "quota-axi": {"current":"0.1.6","wanted":"0.1.9","latest":"0.1.9"},
  "@openai/codex": {"current":"1.0.0","wanted":"2.0.0","latest":"2.0.0"}
}
JSON
  write_release "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" v2.1.0
  write_release "$TEST_FAKE_NO_MISTAKES_RELEASE_JSON" v1.40.0

  json=$(run_checker 1000 --force --json)
  [ "$(printf '%s' "$json" | jq -r '.sources.firstmate.default_branch')" = trunk ] \
    || fail "Firstmate default branch was not resolved from origin"
  [ "$(printf '%s' "$json" | jq -r '.sources.firstmate.behind')" = 1 ] \
    || fail "Firstmate behind count was not parsed"
  [ "$(printf '%s' "$json" | jq -r '.sources.npm_global.packages[0].name')" = quota-axi ] \
    || fail "scoped npm update was not parsed"
  [ "$(printf '%s' "$json" | jq '.sources.npm_global.packages | length')" -eq 1 ] \
    || fail "unrelated global npm package leaked into the result"
  [ "$(printf '%s' "$json" | jq -r '.sources.treehouse.status')" = update_available ] \
    || fail "treehouse release response was not compared"
  [ "$(printf '%s' "$json" | jq -r '.sources.no_mistakes.status')" = up_to_date ] \
    || fail "no-mistakes up-to-date response was not compared"
  [ "$(printf '%s' "$json" | jq -r '.sources.nix_pinned.status')" = excluded ] \
    || fail "nix-pinned exclusion is absent from JSON"

  human=$(run_checker 1001)
  assert_contains "$human" "firstmate: 1 behind (origin/trunk)" "human Firstmate summary changed"
  assert_contains "$human" "npm-global: quota-axi 0.1.6 -> 0.1.9" "human npm summary changed"
  assert_contains "$human" "treehouse: v2.0.0 -> v2.1.0" "human treehouse summary changed"
  assert_contains "$human" "no-mistakes: up to date" "human no-mistakes summary changed"
  assert_contains "$human" "nix-pinned tools are intentionally not tracked here" "human nix exclusion changed"

  calls_before=$(wc -l < "$TEST_FAKE_CALL_LOG" | tr -d ' ')
  startup=$(run_checker 999999 --startup)
  calls_after=$(wc -l < "$TEST_FAKE_CALL_LOG" | tr -d ' ')
  [ "$calls_after" -eq "$calls_before" ] || fail "startup mode contacted publication sources"
  assert_contains "$startup" "dev-tools: updates available" "startup summary lost its prefix"
  assert_contains "$startup" "firstmate 1 behind" "startup summary omitted Firstmate"
  assert_contains "$startup" "quota-axi 0.1.6 -> 0.1.9" "startup summary omitted npm update"
  assert_contains "$startup" "treehouse v2.0.0 -> v2.1.0" "startup summary omitted treehouse"
  assert_not_contains "$startup" "no-mistakes v1.40.0" "startup summary included an up-to-date source"
  pass "checker parses and renders every scoped source"
}

test_fail_soft_unknowns() {
  local base repo json human
  base="$TMP_ROOT/unknown"
  repo="$base/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b odd-default
  git -C "$repo" commit -q --allow-empty -m init
  TEST_REPO="$repo"
  configure_fixture "$base"
  TEST_FAKE_NPM_RC=42
  TEST_FAKE_NO_MISTAKES_VERSION='unexpected version output'
  export TEST_FAKE_NPM_RC TEST_FAKE_NO_MISTAKES_VERSION
  printf '{}\n' > "$TEST_FAKE_NPM_JSON"
  write_release "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" latest
  write_release "$TEST_FAKE_NO_MISTAKES_RELEASE_JSON" v9.0.0

  json=$(run_checker 2000 --force --json) || fail "checker returned non-zero for unavailable sources"
  [ "$(printf '%s' "$json" | jq '[.sources.firstmate,.sources.npm_global,.sources.treehouse,.sources.no_mistakes] | map(select(.status == "unknown")) | length')" -eq 4 ] \
    || fail "unavailable sources did not all degrade to unknown"
  human=$(run_checker 2001)
  assert_contains "$human" "firstmate: unknown" "human output hid Firstmate failure"
  assert_contains "$human" "npm-global: unknown" "human output hid npm failure"
  assert_contains "$human" "treehouse: unknown" "human output hid treehouse failure"
  assert_contains "$human" "no-mistakes: unknown" "human output hid no-mistakes failure"
  pass "source failures are fail-soft unknown results"
}

test_cache_ttl_force_and_silent_startup() {
  local base first second expired forced current startup calls_first calls_cached calls_expired
  base="$TMP_ROOT/cache"
  TEST_REPO=$(make_git_world cache-git)
  configure_fixture "$base"
  TEST_TTL=10
  printf '{"quota-axi":{"current":"0.1.6","latest":"0.1.9"}}\n' > "$TEST_FAKE_NPM_JSON"
  write_release "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" v2.1.0
  write_release "$TEST_FAKE_NO_MISTAKES_RELEASE_JSON" v1.40.0

  first=$(run_checker 3000 --json)
  calls_first=$(wc -l < "$TEST_FAKE_CALL_LOG" | tr -d ' ')
  printf '{"quota-axi":{"current":"0.1.6","latest":"0.1.10"}}\n' > "$TEST_FAKE_NPM_JSON"
  write_release "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" v2.2.0
  second=$(run_checker 3009 --json)
  calls_cached=$(wc -l < "$TEST_FAKE_CALL_LOG" | tr -d ' ')
  [ "$calls_cached" -eq "$calls_first" ] || fail "fresh cache still called publication sources"
  [ "$(printf '%s' "$second" | jq -r '.sources.treehouse.latest')" = v2.1.0 ] \
    || fail "fresh cache did not retain its collected result"

  expired=$(run_checker 3010 --json)
  calls_expired=$(wc -l < "$TEST_FAKE_CALL_LOG" | tr -d ' ')
  [ "$calls_expired" -gt "$calls_cached" ] || fail "TTL boundary did not refresh publication sources"
  [ "$(printf '%s' "$expired" | jq -r '.sources.treehouse.latest')" = v2.2.0 ] \
    || fail "expired cache did not collect the new release"

  write_release "$TEST_FAKE_TREEHOUSE_RELEASE_JSON" v2.3.0
  forced=$(run_checker 3011 --force --json)
  [ "$(printf '%s' "$forced" | jq -r '.sources.treehouse.latest')" = v2.3.0 ] \
    || fail "--force did not bypass a fresh cache"
  [ "$(printf '%s' "$first" | jq -r '.checked_at_epoch')" = 3000 ] \
    || fail "cache did not record the injected collection time"

  current=$(printf '%s' "$forced" | jq '
    .sources.firstmate.status = "up_to_date"
    | .sources.firstmate.behind = 0
    | .sources.npm_global.status = "up_to_date"
    | .sources.npm_global.packages = []
    | .sources.treehouse.status = "up_to_date"
    | .sources.no_mistakes.status = "up_to_date"
  ')
  printf '%s\n' "$current" > "$TEST_HOME/cache.json"
  startup=$(run_checker 999999 --startup)
  [ -z "$startup" ] || fail "startup mode printed when all cached tools were current"
  unset TEST_TTL
  pass "cache honors TTL and force while startup stays cache-only and quiet"
}

test_chrome_headless_health() {
  local base human json startup
  base="$TMP_ROOT/health"
  TEST_REPO="$base/unused-repo"
  configure_fixture "$base"

  human=$(run_checker 4000 --health)
  assert_contains "$human" "chrome-devtools headless flags: healthy" "healthy flags were not reported"
  [ ! -e "$TEST_FAKE_CALL_LOG" ] || fail "health mode contacted publication sources"
  json=$(run_checker 4001 --health --json)
  [ "$(printf '%s' "$json" | jq -r '.checks.chrome_devtools_headless.status')" = healthy ] \
    || fail "health JSON did not report healthy flags"
  [ "$(printf '%s' "$json" | jq '.checks.chrome_devtools_headless.required_flags | length')" -eq 3 ] \
    || fail "health JSON did not preserve the three required flags"

  TEST_FAKE_CHROME_ARGS='--no-sandbox --disable-dev-shm-usage'
  export TEST_FAKE_CHROME_ARGS
  human=$(run_checker 4002 --health)
  assert_contains "$human" "broken (missing required flags: --disable-gpu)" "missing flag was not reported as broken"
  startup=$(run_checker 4003 --startup)
  assert_contains "$startup" "dev-tools: chrome-devtools headless flags broken" "startup hid broken headless flags"

  TEST_FAKE_PRINTENV_RC=1
  export TEST_FAKE_PRINTENV_RC
  human=$(run_checker 4004 --health)
  assert_contains "$human" "broken (CHROME_DEVTOOLS_AXI_CHROME_ARGS is unset)" "unset flag environment was not reported as broken"

  TEST_FAKE_PRINTENV_RC=2
  export TEST_FAKE_PRINTENV_RC
  json=$(run_checker 4005 --health --json) || fail "unknown health state returned non-zero"
  [ "$(printf '%s' "$json" | jq -r '.checks.chrome_devtools_headless.status')" = unknown ] \
    || fail "unreadable environment did not degrade to unknown"
  pass "chrome-devtools health covers healthy, broken, unknown, and startup visibility"
}

export GIT_AUTHOR_NAME=dev-tools-test
export GIT_AUTHOR_EMAIL=dev-tools-test@example.invalid
export GIT_COMMITTER_NAME=dev-tools-test
export GIT_COMMITTER_EMAIL=dev-tools-test@example.invalid
test_source_parsing_and_summaries
test_fail_soft_unknowns
test_cache_ttl_force_and_silent_startup
test_chrome_headless_health
