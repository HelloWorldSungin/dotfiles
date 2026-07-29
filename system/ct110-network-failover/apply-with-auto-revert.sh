#!/usr/bin/env bash
set -euo pipefail

CTID=${CTID:-110}
REVERT_SECONDS=${REVERT_SECONDS:-180}
APPLY_UNIT_NAME=fm-ct110-network-apply-revert
E2E_UNIT_NAME=fm-ct110-failover-e2e-revert
UNIT_NAME=$APPLY_UNIT_NAME
LOCK_FILE=/run/lock/ct110-network-failover.lock
RECOVERY_MARKER=/var/lib/vz/snippets/ct110-network-failover-recovery.pending
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if (( EUID != 0 )); then
  printf 'Run this script as root on the Proxmox host.\n' >&2
  exit 1
fi
if ! command -v pct >/dev/null 2>&1; then
  printf 'pct is required; run this on the Proxmox host, not inside CT110.\n' >&2
  exit 1
fi
if ! command -v flock >/dev/null 2>&1; then
  printf 'flock is required on the Proxmox host.\n' >&2
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

rollback_dir=/var/lib/vz/snippets/ct110-network-failover-rollback
mkdir -p "$rollback_dir"
if pct exec "$CTID" -- systemctl is-enabled --quiet vpn-ethernet-failover.service; then
  service_was_enabled=yes
else
  service_was_enabled=no
fi
if pct exec "$CTID" -- systemctl is-active --quiet vpn-ethernet-failover.service; then
  service_was_active=yes
else
  service_was_active=no
fi

# Snapshot the files this package owns. Missing files get .absent markers.
targets=(
  /etc/systemd/network/eth0.network.d/10-vpn-ethernet-failover.conf
  /etc/systemd/network/eth1.network.d/10-vpn-ethernet-failover.conf
  /etc/systemd/system/vpn-ethernet-failover.service
  /usr/local/libexec/vpn-ethernet-failover
  /usr/local/share/doc/ct110-network-failover/README.md
)
rm -rf "$rollback_dir/files"
mkdir -p "$rollback_dir/files"
for target in "${targets[@]}"; do
  encoded=${target#/}
  mkdir -p "$rollback_dir/files/$(dirname "$encoded")"
  if pct exec "$CTID" -- test -e "$target"; then
    pct pull "$CTID" "$target" "$rollback_dir/files/$encoded"
  else
    touch "$rollback_dir/files/$encoded.absent"
  fi
done

cat >"$rollback_dir/rollback.sh" <<EOF
#!/usr/bin/env bash
set -u
CTID=$CTID
backup=$rollback_dir/files
service_was_enabled=$service_was_enabled
service_was_active=$service_was_active
recovery_marker=$RECOVERY_MARKER
recovery_failed=0
attempt() {
  "\$@" || recovery_failed=1
}
# Stop the route manager first, then add a temporary preferred copy of the
# previously working VPN route before restoring any files.
attempt pct exec "\$CTID" -- sh -c \
  "systemctl stop vpn-ethernet-failover.service >/dev/null 2>&1 || ! systemctl is-active --quiet vpn-ethernet-failover.service"
attempt pct exec "\$CTID" -- ip -4 route replace default via 192.168.50.1 dev eth1 metric 10
for target in ${targets[*]}; do
  encoded=\${target#/}
  if [[ -e "\$backup/\$encoded.absent" ]]; then
    attempt pct exec "\$CTID" -- rm -f "\$target"
  elif [[ -e "\$backup/\$encoded" ]]; then
    attempt pct exec "\$CTID" -- mkdir -p "\$(dirname "\$target")"
    attempt pct push "\$CTID" "\$backup/\$encoded" "\$target"
  else
    printf 'Missing recovery snapshot for %s\n' "\$target" >&2
    recovery_failed=1
  fi
done
attempt pct exec "\$CTID" -- systemctl daemon-reload
# networkctl reload is deliberately non-disruptive and closes Proxmox's stale-config gap.
attempt pct exec "\$CTID" -- networkctl reload
if [[ \$service_was_enabled == yes ]]; then
  attempt pct exec "\$CTID" -- systemctl enable vpn-ethernet-failover.service
else
  attempt pct exec "\$CTID" -- sh -c \
    "systemctl disable vpn-ethernet-failover.service >/dev/null 2>&1 || ! systemctl is-enabled --quiet vpn-ethernet-failover.service"
fi
if [[ \$service_was_active == yes ]]; then
  attempt pct exec "\$CTID" -- systemctl start vpn-ethernet-failover.service
else
  # Restore PVE's unmetered default before removing the temporary metric-10 route.
  attempt pct exec "\$CTID" -- ip -4 route replace default via 192.168.50.1 dev eth1
  attempt pct exec "\$CTID" -- sh -c \
    "ip -4 route del default via 192.168.50.1 dev eth1 metric 10 2>/dev/null || { routes=\$(ip -4 route show default) || exit 1; ! printf '%s\\n' \"\$routes\" | grep -Eq 'via 192\\.168\\.50\\.1 dev eth1 .*metric 10([[:space:]]|\$)'; }"
fi
attempt pct exec "\$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace
if (( recovery_failed == 0 )); then
  rm -f "\$recovery_marker" || recovery_failed=1
fi
exit "\$recovery_failed"
EOF
chmod 700 "$rollback_dir/rollback.sh"

printf '%s\n' apply >"$RECOVERY_MARKER"
if ! systemd-run --unit="$UNIT_NAME" --on-active="${REVERT_SECONDS}s" "$rollback_dir/rollback.sh"; then
  rm -f "$RECOVERY_MARKER"
  exit 1
fi
printf 'Armed %ss host-side auto-revert before touching CT110.\n' "$REVERT_SECONDS"

install_from_repo() {
  local source=$1 target=$2 mode=$3
  pct exec "$CTID" -- mkdir -p "$(dirname "$target")"
  pct push "$CTID" "$source" "$target"
  pct exec "$CTID" -- chmod "$mode" "$target"
}

install_from_repo "$source_dir/eth0-failover.conf" /etc/systemd/network/eth0.network.d/10-vpn-ethernet-failover.conf 0644
install_from_repo "$source_dir/eth1-failover.conf" /etc/systemd/network/eth1.network.d/10-vpn-ethernet-failover.conf 0644
install_from_repo "$source_dir/vpn-ethernet-failover.service" /etc/systemd/system/vpn-ethernet-failover.service 0644
install_from_repo "$source_dir/vpn-ethernet-failover" /usr/local/libexec/vpn-ethernet-failover 0755
install_from_repo "$source_dir/README.md" /usr/local/share/doc/ct110-network-failover/README.md 0644

pct exec "$CTID" -- systemctl daemon-reload
# PVE regenerates .network files without applying them. Always reload explicitly.
pct exec "$CTID" -- networkctl reload
pct exec "$CTID" -- systemctl enable vpn-ethernet-failover.service
# Restart, rather than merely start, so executable and unit updates take effect.
pct exec "$CTID" -- systemctl restart vpn-ethernet-failover.service

# Require the service's three positive probes plus margin before validation.
sleep 25
pct exec "$CTID" -- systemctl is-active --quiet vpn-ethernet-failover.service
pct exec "$CTID" -- sh -c "ip -4 route show default | grep -Eq '^default via 192\\.168\\.68\\.1 dev eth0 .*metric 500([[:space:]]|$)'"
pct exec "$CTID" -- sh -c "ip -4 route show default | grep -Eq '^default via 192\\.168\\.50\\.1 dev eth1 .*metric 100([[:space:]]|$)'"
pct exec "$CTID" -- curl --interface eth0 --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace >/dev/null
pct exec "$CTID" -- curl --interface eth1 --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://1.1.1.1/cdn-cgi/trace >/dev/null
pct exec "$CTID" -- curl --ipv4 --silent --show-error --fail --connect-timeout 4 --max-time 10 https://api.ipify.org
printf '\nLive routes and both egress paths verified. Cancelling auto-revert.\n'
systemctl stop "$UNIT_NAME.timer"
if systemctl is-active --quiet "$UNIT_NAME.service" ||
  systemctl is-failed --quiet "$UNIT_NAME.service" ||
  [[ ! -e $RECOVERY_MARKER ]]; then
  printf 'The apply rollback started before cancellation; recovery state remains authoritative.\n' >&2
  exit 1
fi
systemctl reset-failed "$UNIT_NAME.service" 2>/dev/null || true
rm -f "$RECOVERY_MARKER"
