#!/usr/bin/env bash
set -euo pipefail

CTID=${CTID:-110}
REVERT_SECONDS=${REVERT_SECONDS:-180}
UNIT_NAME=fm-ct110-failover-e2e-revert
TEST_DESTINATION=1.1.1.1
DROPIN_DIR=/run/systemd/system/vpn-ethernet-failover.service.d
DROPIN=$DROPIN_DIR/90-e2e-failure-injection.conf

if (( EUID != 0 )) || ! command -v pct >/dev/null 2>&1; then
  printf 'Run this script as root on the Proxmox host.\n' >&2
  exit 1
fi

# First prove the simple scoped path that the test will later make unreachable.
# This avoids turning a broken test endpoint into a false network finding.
pct exec "$CTID" -- curl --interface eth1 --ipv4 --silent --show-error --fail \
  --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace >/dev/null

rollback=/var/lib/vz/snippets/ct110-failover-e2e-rollback.sh
cat >"$rollback" <<EOF
#!/usr/bin/env bash
set -u
pct exec $CTID -- ip -4 route del unreachable $TEST_DESTINATION metric 1 2>/dev/null || true
pct exec $CTID -- rm -f $DROPIN
pct exec $CTID -- systemctl daemon-reload
pct exec $CTID -- systemctl restart vpn-ethernet-failover.service
EOF
chmod 700 "$rollback"

systemctl stop "$UNIT_NAME.timer" "$UNIT_NAME.service" 2>/dev/null || true
systemctl reset-failed "$UNIT_NAME.service" 2>/dev/null || true
systemd-run --unit="$UNIT_NAME" --on-active="${REVERT_SECONDS}s" "$rollback"
printf 'Armed %ss host-side auto-revert before failure simulation.\n' "$REVERT_SECONDS"

# Pin only this E2E run to the already-proven Cloudflare destination. Making
# that one destination unreachable gives every bound eth1 health connection a
# deterministic failure without interrupting the captain's unrelated sessions.
pct exec "$CTID" -- mkdir -p "$DROPIN_DIR"
printf '%s\n' \
  '[Service]' \
  'Environment="PROBE_URLS=https://1.1.1.1/cdn-cgi/trace"' \
  > /tmp/ct110-vpn-ethernet-failover-e2e.conf
pct push "$CTID" /tmp/ct110-vpn-ethernet-failover-e2e.conf "$DROPIN"
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart vpn-ethernet-failover.service

before=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://api.ipify.org)
pct exec "$CTID" -- ip -4 route add unreachable "$TEST_DESTINATION" metric 1

# Three failed probes are required. Poll with a bounded deadline rather than
# assuming timing, and leave the rollback armed on every failure exit.
deadline=$((SECONDS + 40))
until pct exec "$CTID" -- sh -c "test \"\$(cat /var/lib/vpn-ethernet-failover/state)\" = home"; do
  (( SECONDS < deadline )) || { printf 'Timed out waiting for failover.\n' >&2; exit 1; }
  sleep 2
done
# Reproduce Proxmox's stale-config edge while failed over: networkd will read
# the healthy metric from disk, and the running daemon must reconcile it back.
pct exec "$CTID" -- networkctl reload
deadline=$((SECONDS + 15))
until pct exec "$CTID" -- ip -4 route get 8.8.8.8 | grep -q 'dev eth0'; do
  (( SECONDS < deadline )) || { printf 'Daemon did not reconcile a networkd reload while failed over.\n' >&2; exit 1; }
  sleep 1
done
home_route=$(pct exec "$CTID" -- ip -4 route get 8.8.8.8)
home_ip=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://api.ipify.org)
printf 'Failover: route=%s egress=%s (before=%s)\n' "$home_route" "$home_ip" "$before"
[[ $home_route == *'dev eth0'* ]] || { printf 'Default egress did not move to eth0.\n' >&2; exit 1; }
[[ $home_ip != "$before" ]] || { printf 'Egress identity did not change during failover.\n' >&2; exit 1; }

pct exec "$CTID" -- ip -4 route del unreachable "$TEST_DESTINATION" metric 1
# The same simple request must positively prove eth1 recovery before failback.
pct exec "$CTID" -- curl --interface eth1 --ipv4 --silent --show-error --fail \
  --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace >/dev/null

deadline=$((SECONDS + 40))
until pct exec "$CTID" -- sh -c "test \"\$(cat /var/lib/vpn-ethernet-failover/state)\" = vpn"; do
  (( SECONDS < deadline )) || { printf 'Timed out waiting for failback.\n' >&2; exit 1; }
  sleep 2
done
vpn_route=$(pct exec "$CTID" -- ip -4 route get 8.8.8.8)
vpn_ip=$(pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://api.ipify.org)
printf 'Failback: route=%s egress=%s\n' "$vpn_route" "$vpn_ip"
[[ $vpn_route == *'dev eth1'* ]] || { printf 'Default egress did not return to eth1.\n' >&2; exit 1; }
[[ $vpn_ip == "$before" ]] || { printf 'VPN egress identity was not restored.\n' >&2; exit 1; }

pct exec "$CTID" -- journalctl -u vpn-ethernet-failover.service --since '-3 minutes' --no-pager |
  grep -E 'transition (vpn->home|home->vpn)'

# Restore the production endpoint set before cancelling the timer.
pct exec "$CTID" -- rm -f "$DROPIN"
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart vpn-ethernet-failover.service
pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://api.ipify.org >/dev/null
systemctl stop "$UNIT_NAME.timer"
systemctl reset-failed "$UNIT_NAME.service" 2>/dev/null || true
rm -f /tmp/ct110-vpn-ethernet-failover-e2e.conf
printf 'Failover and positive-proof failback passed; production probes restored and auto-revert cancelled.\n'
