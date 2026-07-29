#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
program="$repo_root/system/ct110-network-failover/vpn-ethernet-failover"
apply_script="$repo_root/system/ct110-network-failover/apply-with-auto-revert.sh"
e2e_script="$repo_root/system/ct110-network-failover/e2e-failover-test.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1 text=$2
  grep -Fq -- "$text" "$file" || fail "$file does not contain: $text"
}

make_fakes() {
  local case_dir=$1
  mkdir -p "$case_dir/bin" "$case_dir/state"

  cat >"$case_dir/bin/ip" <<'FAKE_IP'
#!/usr/bin/env bash
set -euo pipefail
routes=${FAKE_ROUTES:?}
if [[ $* == '-4 -o route show default' ]]; then
  cat "$routes"
  exit 0
fi
if [[ $1 == -4 && $2 == route && $3 == add ]]; then
  shift 3
  printf '%s\n' "$*" >>"$routes"
  exit 0
fi
if [[ $1 == -4 && $2 == route && $3 == del ]]; then
  shift 3
  target=$*
  awk -v target="$target" 'BEGIN { removed=0 } !removed && $0 == target { removed=1; next } { print } END { if (!removed) exit 1 }' "$routes" >"$routes.new"
  mv "$routes.new" "$routes"
  exit 0
fi
printf 'unexpected fake ip call: %s\n' "$*" >&2
exit 1
FAKE_IP

  cat >"$case_dir/bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_CURL_CALLS:?}"
read -r result <"${FAKE_RESULTS:?}"
tail -n +2 "$FAKE_RESULTS" >"$FAKE_RESULTS.new"
mv "$FAKE_RESULTS.new" "$FAKE_RESULTS"
[[ $result == success ]]
FAKE_CURL

  cat >"$case_dir/bin/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
set -euo pipefail
if [[ -s ${FAKE_INJECT_ROUTE:-} && ! -e ${FAKE_INJECT_ROUTE}.done ]]; then
  cat "$FAKE_INJECT_ROUTE" >>"${FAKE_ROUTES:?}"
  touch "${FAKE_INJECT_ROUTE}.done"
fi
exit 0
FAKE_SLEEP
  chmod +x "$case_dir/bin/"*
}

run_case() {
  local case_dir=$1 probes=$2
  FAKE_ROUTES="$case_dir/routes" \
  FAKE_RESULTS="$case_dir/results" \
  FAKE_CURL_CALLS="$case_dir/curl-calls" \
  FAKE_INJECT_ROUTE="$case_dir/inject-route" \
  IP_BIN="$case_dir/bin/ip" \
  CURL_BIN="$case_dir/bin/curl" \
  SLEEP_BIN="$case_dir/bin/sleep" \
  STATE_DIRECTORY="$case_dir/state" \
  STATE_FILE="$case_dir/state/current" \
  PROBE_URLS="https://probe.invalid/generate_204" \
  PROBE_INTERVAL_SECONDS=0 \
  MAX_PROBES="$probes" \
  ALLOW_NON_ROOT_FOR_TESTS=1 \
  "$program" >"$case_dir/log" 2>&1
}

# Two failures are not enough, and a success resets the failure streak.
case_failover="$tmp/failover"
make_fakes "$case_failover"
cat >"$case_failover/routes" <<'ROUTES'
default via 192.168.50.1 dev eth1 proto boot
default via 192.168.50.1 dev eth1 proto static metric 100
default via 192.168.68.1 dev eth0 proto static metric 500
ROUTES
printf 'vpn\n' >"$case_failover/state/current"
printf '%s\n' success success success failure failure success failure failure failure >"$case_failover/results"
# Simulate networkctl re-adding PVE's unmetered gateway while the daemon runs.
printf '%s\n' 'default via 192.168.50.1 dev eth1 proto static' >"$case_failover/inject-route"
run_case "$case_failover" 9
[[ $(<"$case_failover/state/current") == home ]] || fail 'did not enter home state'
assert_contains "$case_failover/routes" 'default via 192.168.50.1 dev eth1 proto static metric 1000'
assert_contains "$case_failover/routes" 'default via 192.168.68.1 dev eth0 proto static metric 500'
[[ $(grep -Fc -- 'default via 192.168.50.1' "$case_failover/routes") == 1 ]] || fail 'stale PVE VPN route was not reconciled'
[[ $(grep -Fc -- 'transition vpn->home after 3 consecutive failed' "$case_failover/log") == 1 ]] || fail 'failover transition was not logged exactly once'
[[ $(wc -l <"$case_failover/curl-calls") == 9 ]] || fail 'unexpected failover probe count'
assert_contains "$case_failover/curl-calls" '--interface eth1'

# Two successes are not enough, and a failure resets the recovery streak.
case_failback="$tmp/failback"
make_fakes "$case_failback"
cat >"$case_failback/routes" <<'ROUTES'
default via 192.168.50.1 dev eth1 proto static metric 1000
default via 192.168.68.1 dev eth0 proto static metric 500
ROUTES
printf 'home\n' >"$case_failback/state/current"
printf '%s\n' success success failure success success success >"$case_failback/results"
run_case "$case_failback" 6
[[ $(<"$case_failback/state/current") == vpn ]] || fail 'did not return to vpn state'
assert_contains "$case_failback/routes" 'default via 192.168.50.1 dev eth1 proto static metric 100'
[[ $(grep -Fc -- 'transition home->vpn after 3 consecutive successful' "$case_failback/log") == 1 ]] || fail 'failback transition was not logged exactly once'

# A startup with persisted VPN state still requires three fresh positive probes.
case_initial="$tmp/initial"
make_fakes "$case_initial"
cat >"$case_initial/routes" <<'ROUTES'
default via 192.168.50.1 dev eth1 proto static metric 100
default via 192.168.68.1 dev eth0 proto static metric 500
ROUTES
printf 'vpn\n' >"$case_initial/state/current"
printf '%s\n' success success >"$case_initial/results"
run_case "$case_initial" 2
[[ $(<"$case_initial/state/current") == home ]] || fail 'startup trusted persisted VPN state without fresh proof'
assert_contains "$case_initial/routes" 'default via 192.168.50.1 dev eth1 proto static metric 1000'
assert_contains "$case_initial/log" 'started in home safety state; persisted=vpn'

# The third consecutive startup success promotes the VPN.
printf '%s\n' success success success >"$case_initial/results"
run_case "$case_initial" 3
[[ $(<"$case_initial/state/current") == vpn ]] || fail 'startup did not select VPN after positive proof'
assert_contains "$case_initial/log" 'transition home->vpn after 3 consecutive successful'

grep -Fq 'Metric=1000' "$repo_root/system/ct110-network-failover/eth1-failover.conf" ||
  fail 'static eth1 route is VPN-preferred'

apply_lock=$(sed -n 's/^LOCK_FILE=//p' "$apply_script")
e2e_lock=$(sed -n 's/^LOCK_FILE=//p' "$e2e_script")
[[ -n $apply_lock && $apply_lock == "$e2e_lock" ]] || fail 'host operations do not share one lock'
apply_marker=$(sed -n 's/^RECOVERY_MARKER=//p' "$apply_script")
e2e_marker=$(sed -n 's/^RECOVERY_MARKER=//p' "$e2e_script")
[[ -n $apply_marker && $apply_marker == "$e2e_marker" ]] || fail 'host operations do not share one recovery marker'
assert_contains "$apply_script" 'for unit in "$APPLY_UNIT_NAME" "$E2E_UNIT_NAME"; do'
assert_contains "$e2e_script" 'for unit in "$APPLY_UNIT_NAME" "$E2E_UNIT_NAME"; do'
assert_contains "$apply_script" 'exit "\$recovery_failed"'
assert_contains "$e2e_script" 'exit "\$recovery_failed"'
assert_contains "$apply_script" 'stop_originating_workflow || exit 1'
assert_contains "$e2e_script" 'stop_originating_workflow || exit 1'
assert_contains "$apply_script" 'flock -w 15 9 || exit 1'
assert_contains "$e2e_script" 'flock -w 15 9 || exit 1'
assert_contains "$apply_script" '--property=KillMode=control-group'
assert_contains "$e2e_script" '--property=KillMode=control-group'
assert_contains "$e2e_script" 'MIN_REVERT_SECONDS=$((WORKFLOW_BUDGET_SECONDS + ROLLBACK_MARGIN_SECONDS))'
assert_contains "$e2e_script" 'WORKFLOW_DEADLINE=$((SECONDS + REVERT_SECONDS - ROLLBACK_MARGIN_SECONDS))'

printf 'vpn-ethernet-failover tests passed\n'
