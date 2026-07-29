#!/usr/bin/env bash
set -euo pipefail

CTID=${CTID:-110}
REVERT_SECONDS=${REVERT_SECONDS:-240}
APPLY_UNIT_NAME=fm-ct110-network-apply-revert
E2E_UNIT_NAME=fm-ct110-failover-e2e-revert
UNIT_NAME=$E2E_UNIT_NAME
LOCK_FILE=/run/lock/ct110-network-failover.lock
RECOVERY_MARKER=/var/lib/vz/snippets/ct110-network-failover-recovery.pending
TEST_DESTINATION=1.1.1.1
DROPIN_DIR=/run/systemd/system/vpn-ethernet-failover.service.d
DROPIN=$DROPIN_DIR/90-e2e-failure-injection.conf
STARTUP_WAIT_SECONDS=40
FAILOVER_WAIT_SECONDS=40
RECONCILE_WAIT_SECONDS=15
FAILBACK_WAIT_SECONDS=40
CURL_MAX_TIME_SECONDS=10
ROLLBACK_MARGIN_SECONDS=30
WORKFLOW_BUDGET_SECONDS=$((STARTUP_WAIT_SECONDS + FAILOVER_WAIT_SECONDS + RECONCILE_WAIT_SECONDS + FAILBACK_WAIT_SECONDS + (5 * CURL_MAX_TIME_SECONDS)))
MIN_REVERT_SECONDS=$((WORKFLOW_BUDGET_SECONDS + ROLLBACK_MARGIN_SECONDS))

if (( EUID != 0 )) || ! command -v pct >/dev/null 2>&1; then
  printf 'Run this script as root on the Proxmox host.\n' >&2
  exit 1
fi
if ! command -v flock >/dev/null 2>&1; then
  printf 'flock is required on the Proxmox host.\n' >&2
  exit 1
fi
if (( REVERT_SECONDS < MIN_REVERT_SECONDS )); then
  printf 'REVERT_SECONDS must be at least %s for the bounded E2E workflow.\n' "$MIN_REVERT_SECONDS" >&2
  exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  printf 'Another CT110 network failover operation is in progress.\n' >&2
  exit 1
fi

recovery_pending() {
  local unit
  [[ -e $RECOVERY_MARKER ]] && return 0
  for unit in "$APPLY_UNIT_NAME" "$E2E_UNIT_NAME"; do
    if systemctl is-active --quiet "$unit.timer" ||
      systemctl is-active --quiet "$unit.service" ||
      systemctl is-failed --quiet "$unit.timer" ||
      systemctl is-failed --quiet "$unit.service"; then
      return 0
    fi
  done
  return 1
}

if recovery_pending; then
  printf 'A prior CT110 network recovery is active or unresolved; preserve and resolve it before retrying.\n' >&2
  exit 1
fi

payload=$(mktemp /tmp/ct110-vpn-ethernet-failover-e2e.XXXXXX)
trap 'rm -f -- "$payload"' EXIT

# First prove the simple scoped path that the test will later make unreachable.
# This avoids turning a broken test endpoint into a false network finding.
pct exec "$CTID" -- curl --interface eth1 --ipv4 --silent --show-error --fail \
  --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace >/dev/null

rollback=/var/lib/vz/snippets/ct110-failover-e2e-rollback.sh
cat >"$rollback" <<EOF
#!/usr/bin/env bash
set -u
CTID=$CTID
recovery_marker=$RECOVERY_MARKER
recovery_failed=0
attempt() {
  "\$@" || recovery_failed=1
}
attempt pct exec "\$CTID" -- sh -c \
  "ip -4 route del unreachable $TEST_DESTINATION metric 1 2>/dev/null || { routes=\$(ip -4 route show type unreachable $TEST_DESTINATION) || exit 1; test -z \"\$routes\"; }"
attempt pct exec "\$CTID" -- rm -f $DROPIN
attempt pct exec "\$CTID" -- systemctl daemon-reload
attempt pct exec "\$CTID" -- systemctl restart vpn-ethernet-failover.service
attempt pct exec "\$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time $CURL_MAX_TIME_SECONDS https://1.1.1.1/cdn-cgi/trace
if (( recovery_failed == 0 )); then
  rm -f "\$recovery_marker" || recovery_failed=1
fi
exit "\$recovery_failed"
EOF
chmod 700 "$rollback"

printf '%s\n' e2e >"$RECOVERY_MARKER"
if ! systemd-run --unit="$UNIT_NAME" --on-active="${REVERT_SECONDS}s" "$rollback"; then
  rm -f "$RECOVERY_MARKER"
  exit 1
fi
WORKFLOW_DEADLINE=$((SECONDS + REVERT_SECONDS - ROLLBACK_MARGIN_SECONDS))
printf 'Armed %ss host-side auto-revert before failure simulation.\n' "$REVERT_SECONDS"

set_phase_deadline() {
  local budget=$1
  deadline=$((SECONDS + budget))
  if (( deadline > WORKFLOW_DEADLINE )); then
    deadline=$WORKFLOW_DEADLINE
  fi
}

require_remaining_time() {
  local budget=$1 phase=$2
  if (( SECONDS + budget > WORKFLOW_DEADLINE )); then
    printf 'Overall E2E deadline reached before %s.\n' "$phase" >&2
    exit 1
  fi
}

# Pin only this E2E run to the already-proven Cloudflare destination. Making
# that one destination unreachable gives every bound eth1 health connection a
# deterministic failure without interrupting the captain's unrelated sessions.
pct exec "$CTID" -- mkdir -p "$DROPIN_DIR"
printf '%s\n' \
  '[Service]' \
  'Environment="PROBE_URLS=https://1.1.1.1/cdn-cgi/trace"' \
  >"$payload"
pct push "$CTID" "$payload" "$DROPIN"
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart vpn-ethernet-failover.service

set_phase_deadline "$STARTUP_WAIT_SECONDS"
until pct exec "$CTID" -- sh -c "test \"\$(cat /var/lib/vpn-ethernet-failover/state)\" = vpn"; do
  (( SECONDS < deadline )) || { printf 'Timed out waiting for startup VPN proof.\n' >&2; exit 1; }
  sleep 2
done
require_remaining_time "$CURL_MAX_TIME_SECONDS" 'initial egress identity check'
before=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time "$CURL_MAX_TIME_SECONDS" https://api.ipify.org)
pct exec "$CTID" -- ip -4 route add unreachable "$TEST_DESTINATION" metric 1

# Three failed probes are required. Poll with a bounded deadline rather than
# assuming timing, and leave the rollback armed on every failure exit.
set_phase_deadline "$FAILOVER_WAIT_SECONDS"
until pct exec "$CTID" -- sh -c "test \"\$(cat /var/lib/vpn-ethernet-failover/state)\" = home"; do
  (( SECONDS < deadline )) || { printf 'Timed out waiting for failover.\n' >&2; exit 1; }
  sleep 2
done
# Reproduce Proxmox's stale-config edge while failed over: networkd will replay
# its non-preferred baseline, and the running daemon must retain failed state.
pct exec "$CTID" -- networkctl reload
set_phase_deadline "$RECONCILE_WAIT_SECONDS"
until pct exec "$CTID" -- ip -4 route get 8.8.8.8 | grep -q 'dev eth0'; do
  (( SECONDS < deadline )) || { printf 'Daemon did not reconcile a networkd reload while failed over.\n' >&2; exit 1; }
  sleep 1
done
home_route=$(pct exec "$CTID" -- ip -4 route get 8.8.8.8)
require_remaining_time "$CURL_MAX_TIME_SECONDS" 'home egress identity check'
home_ip=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time "$CURL_MAX_TIME_SECONDS" https://api.ipify.org)
printf 'Failover: route=%s egress=%s (before=%s)\n' "$home_route" "$home_ip" "$before"
[[ $home_route == *'dev eth0'* ]] || { printf 'Default egress did not move to eth0.\n' >&2; exit 1; }
[[ $home_ip != "$before" ]] || { printf 'Egress identity did not change during failover.\n' >&2; exit 1; }

pct exec "$CTID" -- ip -4 route del unreachable "$TEST_DESTINATION" metric 1
# The same simple request must positively prove eth1 recovery before failback.
require_remaining_time "$CURL_MAX_TIME_SECONDS" 'bound eth1 recovery proof'
pct exec "$CTID" -- curl --interface eth1 --ipv4 --silent --show-error --fail \
  --connect-timeout 4 --max-time "$CURL_MAX_TIME_SECONDS" https://1.1.1.1/cdn-cgi/trace >/dev/null

set_phase_deadline "$FAILBACK_WAIT_SECONDS"
until pct exec "$CTID" -- sh -c "test \"\$(cat /var/lib/vpn-ethernet-failover/state)\" = vpn"; do
  (( SECONDS < deadline )) || { printf 'Timed out waiting for failback.\n' >&2; exit 1; }
  sleep 2
done
vpn_route=$(pct exec "$CTID" -- ip -4 route get 8.8.8.8)
require_remaining_time "$CURL_MAX_TIME_SECONDS" 'VPN egress identity check'
vpn_ip=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time "$CURL_MAX_TIME_SECONDS" https://api.ipify.org)
printf 'Failback: route=%s egress=%s\n' "$vpn_route" "$vpn_ip"
[[ $vpn_route == *'dev eth1'* ]] || { printf 'Default egress did not return to eth1.\n' >&2; exit 1; }
[[ $vpn_ip == "$before" ]] || { printf 'VPN egress identity was not restored.\n' >&2; exit 1; }

pct exec "$CTID" -- journalctl -u vpn-ethernet-failover.service --since '-3 minutes' --no-pager |
  grep -E 'transition (vpn->home|home->vpn)'

# Restore the production endpoint set before cancelling the timer.
pct exec "$CTID" -- rm -f "$DROPIN"
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart vpn-ethernet-failover.service
require_remaining_time "$CURL_MAX_TIME_SECONDS" 'production egress verification'
pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time "$CURL_MAX_TIME_SECONDS" https://api.ipify.org >/dev/null
systemctl stop "$UNIT_NAME.timer"
if systemctl is-active --quiet "$UNIT_NAME.service" ||
  systemctl is-failed --quiet "$UNIT_NAME.service" ||
  [[ ! -e $RECOVERY_MARKER ]]; then
  printf 'The E2E rollback started before cancellation; recovery state remains authoritative.\n' >&2
  exit 1
fi
systemctl reset-failed "$UNIT_NAME.service" 2>/dev/null || true
rm -f "$RECOVERY_MARKER"
printf 'Failover and positive-proof failback passed; production probes restored and auto-revert cancelled.\n'
