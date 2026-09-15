#!/usr/bin/env bash
# All installers, binaries, usage readers and run records are isolated fixtures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export TEST_ROOT=$TMP
export DEV_TOOLS_APPLY_RECEIPT_DIR=$TMP/receipts
export DEV_TOOLS_UPDATE_LOCAL_BIN=$TMP/local
export DEV_TOOLS_UPDATE_NPM_PREFIX=$TMP/npm
export DEV_TOOLS_FIRSTMATE_STATE_DIR=$TMP/lanes
export DEV_TOOLS_FIRSTMATE_PATH=$TMP/firstmate
export DEV_TOOLS_APPLY_USAGE_BIN=$TMP/usage
export DEV_TOOLS_UPDATE_CURL_BIN=$TMP/curl
export DEV_TOOLS_APPLY_CHECKER_BIN=$TMP/checker
export DEV_TOOLS_UPDATE_NPM_BIN=$TMP/npm-fixture
export DEV_TOOLS_UPDATE_PLATFORM=linux-amd64
export DEV_TOOLS_PINS_FILE=$TMP/pins
export DEV_TOOLS_APPLY_TIMEOUT_SECONDS=3
export DEV_TOOLS_UPDATE_NETWORK_TIMEOUT_SECONDS=2
mkdir -p "$TMP/receipts" "$TMP/local" "$TMP/npm/bin" "$TMP/lanes" "$TMP/artifact"
printf 'FIRSTMATE_REV=0000000000000000000000000000000000000000\nNPM_TOOL_PINS=("quota-axi|quota-axi|quota-axi|latest|publisher|yes|default")\n' >"$TMP/pins"
cat >"$TMP/usage" <<'EOF'
#!/usr/bin/env bash
set -eu
count=$(cat "$TEST_ROOT/count" 2>/dev/null || printf 0)
printf '%s' "$((count + 1))" >"$TEST_ROOT/count"
status=idle
[ -f "$TEST_ROOT/active-run" ] && status=busy
[ -f "$TEST_ROOT/busy" ] && status=busy
[ -f "$TEST_ROOT/unknown" ] && status=unknown
if [ -f "$TEST_ROOT/new-user" ] && [ "$count" -ge 1 ]; then status=busy; fi
if [ -f "$TEST_ROOT/crash" ]; then kill -KILL "$TEST_UPDATER_PID"; exit 1; fi
jq -cn --arg status "$status" '{schema_version:1,status:$status,detail:$status}'
EOF
cat >"$TMP/checker" <<'EOF'
#!/usr/bin/env bash
set -eu
current=$("$TEST_ROOT/npm/bin/quota-axi" --version 2>/dev/null || printf unknown)
jq -cn --arg current "$current" '{schema_version:4,tools:[{name:"quota-axi",current:$current,latest_stable:"2.0.0"}]}'
EOF
cat >"$TMP/npm-fixture" <<'EOF'
#!/usr/bin/env bash
set -eu
if [ "$1" = view ]; then
  version=${2#*@}; [ "$version" = latest ] && version=2.0.0
  jq -cn --arg v "$version" '{version:$v,"dist.integrity":"sha512-YWJjZA=="}'
elif [ "$1" = install ]; then
  printf '%s\n' "$*" >>"$TEST_ROOT/installs"
  [ ! -f "$TEST_ROOT/fail-install" ] || exit 1
  version=${3#*@}
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$version" >"$TEST_ROOT/npm/bin/quota-axi"
else exit 1
fi
EOF
cat >"$TMP/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
url= output=
while [ "$#" -gt 0 ]; do
  case "$1" in https:*) url=$1 ;; -o) shift; output=$1 ;; esac
  shift
done
[ ! -f "$TEST_ROOT/network-fail" ] || exit 1
case "$url" in
  */releases/latest|*/releases/tags/v2.0.0) cat "$TEST_ROOT/release.json" ;;
  */no-mistakes-v2.0.0-linux-amd64.tar.gz)
    cp "$TEST_ROOT/archive" "$output"
    [ ! -f "$TEST_ROOT/corrupt" ] || printf corrupt >>"$output" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/usage" "$TMP/checker" "$TMP/npm-fixture" "$TMP/curl"
printf '#!/usr/bin/env bash\nprintf "2.0.0\\n"\n' >"$TMP/artifact/no-mistakes"
chmod +x "$TMP/artifact/no-mistakes"
tar -czf "$TMP/archive" -C "$TMP/artifact" no-mistakes
checksum=$(sha256sum "$TMP/archive" | cut -d ' ' -f 1)
jq -n --arg digest "sha256:$checksum" '{tag_name:"v2.0.0",draft:false,prerelease:false,assets:[{name:"no-mistakes-v2.0.0-linux-amd64.tar.gz",digest:$digest,browser_download_url:"https://github.com/kunchenguid/no-mistakes/releases/download/v2.0.0/no-mistakes-v2.0.0-linux-amd64.tar.gz"}]}' >"$TMP/release.json"
reset_tool() {
  printf '#!/usr/bin/env bash\nprintf "1.0.0\\n"\n' >"$TMP/local/no-mistakes"
  cp "$TMP/local/no-mistakes" "$TMP/npm/bin/quota-axi"
  chmod +x "$TMP/local/no-mistakes" "$TMP/npm/bin/quota-axi"
  printf 0 >"$TMP/count"
  jq -n --arg name "${1:-no-mistakes}" '{schema_version:1,tools:[$name]}' >"$TMP/receipts/obligations.json"
}
run() { bash -c 'export TEST_UPDATER_PID=$$; exec bash "$@"' -- "$ROOT/bin/dev-tools-apply-updates" --resume --json >"$TMP/result"; }
assert() { jq -e "$1" "$TMP/result" >/dev/null || { cat "$TMP/result"; exit 1; }; }
reset_tool
# An active run remains busy even when the isolated worker directory is empty.
touch "$TMP/active-run"
run
assert '.tiers.release_binary.status == "deferred" and .obligations.remaining == ["no-mistakes"]'
rm "$TMP/active-run"
run
assert '.tiers.release_binary.status == "applied" and .obligations.remaining == []'
receipt=$(jq -r '.receipt.path' "$TMP/result")
[ "$(stat -c %a "$receipt")" = 600 ]
bash "$ROOT/bin/dev-tools-apply-updates" --rollback "$receipt" --attended --json >"$TMP/result"
assert '.tools[0].status == "rolled_back"'
[ "$("$TMP/local/no-mistakes" --version)" = 1.0.0 ]
printf 'ok - active run after worker exit defers; idle retry applies and attended rollback restores\n'
reset_tool
touch "$TMP/new-user"
run
assert '.tiers.release_binary.status == "deferred" and .obligations.remaining == ["no-mistakes"]'
[ "$("$TMP/local/no-mistakes" --version)" = 1.0.0 ]
rm "$TMP/new-user"
run
assert '.tiers.release_binary.status == "applied"'
printf 'ok - fresh usage check catches new user before binary replacement\n'
for failure in unknown corrupt network-fail; do
  reset_tool
  touch "$TMP/$failure"
  if [ "$failure" = unknown ]; then run; elif run; then exit 1; fi
  assert '.obligations.remaining == ["no-mistakes"]'
  [ "$("$TMP/local/no-mistakes" --version)" = 1.0.0 ]
  rm "$TMP/$failure"
done
reset_tool
DEV_TOOLS_APPLY_USAGE_BIN="$TMP/absent" run
assert '.tiers.release_binary.status == "deferred"'
printf 'ok - unknown usage and missing authority defer; bad integrity and network failure preserve binary\n'
reset_tool
touch "$TMP/crash"
# Kill the updater from its mocked usage reader, then prove kernel lock recovery.
if run 2>/dev/null; then exit 1; fi
rm "$TMP/crash"
run
assert '.tiers.release_binary.status == "applied" and .obligations.remaining == []'
printf 'ok - restart after killed attempt recovers obligation and lock\n'
reset_tool quota-axi
touch "$TMP/new-user"
run
assert '.tiers.npm_global.packages[0].status == "deferred" and .obligations.remaining == ["quota-axi"]'
[ ! -f "$TMP/installs" ]
rm "$TMP/new-user"
run
assert '.tiers.npm_global.packages[0].status == "applied" and .obligations.remaining == []'
printf 'ok - npm uses existing integrity and receipts with fresh usage deferral\n'
reset_tool
touch "$TMP/busy"
bash "$ROOT/bin/dev-tools-apply-updates" --explicit --json >"$TMP/result" || true
assert '.obligations.remaining | index("no-mistakes") != null and index("quota-axi") != null'
rm "$TMP/busy"
printf 'ok - explicit invocation persists requested obligations before attempting work\n'
reset_tool
jq '.prerelease = true' "$TMP/release.json" >"$TMP/preview.json"
cp "$TMP/release.json" "$TMP/stable.json"
mv "$TMP/preview.json" "$TMP/release.json"
if run; then exit 1; fi
assert '.tiers.release_binary.status == "refused" and .obligations.remaining == ["no-mistakes"]'
mv "$TMP/stable.json" "$TMP/release.json"
printf 'ok - publisher prerelease is refused\n'
reset_tool
printf '#!/usr/bin/env bash\nprintf "3.0.0\\n"\n' >"$TMP/local/no-mistakes"
if run; then exit 1; fi
assert '.tiers.release_binary.status == "refused"'
[ "$("$TMP/local/no-mistakes" --version)" = 3.0.0 ]
printf 'ok - newer installed release is preserved\n'
reset_tool
(
  flock -x 8
  if run; then exit 1; fi
) 8>"$TMP/receipts/update.lock"
[ "$("$TMP/local/no-mistakes" --version)" = 1.0.0 ]
printf 'ok - concurrent attempt cannot acquire mutation ownership\n'
reset_tool
run
receipt=$(jq -r '.receipt.path' "$TMP/result")
backup=$(jq -r '.tools[0].prior_evidence.path' "$receipt")
printf broken >"$backup"
if bash "$ROOT/bin/dev-tools-apply-updates" --rollback "$receipt" --attended --json >"$TMP/result"; then exit 1; fi
assert '.tools[0].status == "refused"'
[ "$("$TMP/local/no-mistakes" --version)" = 2.0.0 ]
printf 'ok - rollback refuses changed prior artifact\n'
reset_tool quota-axi
touch "$TMP/fail-install"
if run; then exit 1; fi
assert '.tiers.npm_global.packages[0].status == "failed" and .obligations.remaining == ["quota-axi"]'
rm "$TMP/fail-install"
run
assert '.tiers.npm_global.packages[0].status == "applied" and .obligations.remaining == []'
printf 'ok - failed installer retains obligation for successful retry\n'
reset_tool
touch "$TMP/lanes/worker.meta"
run
assert '.tiers.release_binary.status == "deferred" and .worker_guard.status == "active"'
rm "$TMP/lanes/worker.meta"
printf 'ok - Firstmate active-lane protection remains independent of usage reader\n'
reset_tool
printf '{invalid' >"$TMP/receipts/obligations.json"
if run; then exit 1; fi
[ "$(cat "$TMP/receipts/obligations.json")" = '{invalid' ]
printf 'ok - corrupt obligations are preserved and refused\n'
printf '{"schema_version":1,"tools":[]}' >"$TMP/receipts/obligations.json"
DEV_TOOLS_APPLY_CHECKER_BIN="$TMP/missing-checker" run
assert '.obligations.remaining == [] and .tiers.firstmate.status == "skipped"'
printf 'ok - empty resume requires no discovery or mutation\n'
reset_tool
cp "$TMP/local/no-mistakes" "$TMP/before"
cp "$TMP/usage" "$TMP/valid-usage"
printf '#!/usr/bin/env bash\nprintf "{\\\"status\\\":\\\"idle\\\"}\\n"\n' >"$TMP/usage"
run
assert '.tiers.release_binary.status == "deferred"'
cmp "$TMP/before" "$TMP/local/no-mistakes"
printf '#!/usr/bin/env bash\nsleep 5\n' >"$TMP/usage"
run
assert '.tiers.release_binary.status == "deferred"'
cmp "$TMP/before" "$TMP/local/no-mistakes"
mv "$TMP/valid-usage" "$TMP/usage"
printf 'ok - malformed and timed-out usage responses never authorize replacement\n'
reset_tool
cp "$TMP/artifact/no-mistakes" "$TMP/local/no-mistakes"
run
assert '.tiers.release_binary.status == "up_to_date" and .receipt.status == "none" and .obligations.remaining == []'
printf 'ok - installed stable release converges without replacement or receipt\n'
reset_tool
if DEV_TOOLS_UPDATE_PLATFORM=unsupported run; then exit 1; fi
assert '.tiers.release_binary.status == "refused" and .obligations.remaining == ["no-mistakes"]'
[ "$("$TMP/local/no-mistakes" --version)" = 1.0.0 ]
printf 'ok - unsupported platform override refuses without replacing binary\n'
