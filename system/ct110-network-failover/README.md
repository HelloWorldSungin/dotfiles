# CT110 VPN to home ethernet failover

This is root-level networking for CT110 (`research`), not Home Manager user
configuration. The installer places systemd-networkd drop-ins and a system
service under `/etc` and `/usr/local`.

## Routing and health policy

- `eth1` via `192.168.50.1` is preferred at metric 100 while healthy. That
  gateway's upstream tunnel supplies the VPN exit.
- `eth0` via the proven home gateway `192.168.68.1` stays installed at metric
  500. It is selected when the service raises the failed VPN route to metric
  1000.
- Every five seconds the service makes real HTTPS requests with curl bound to
  `eth1`. Either of two independent HTTP 204 endpoints is accepted.
- Three consecutive failures are required to select home ethernet. Three
  consecutive successes are required to return to the VPN. Opposite results
  reset the streak.
- Probe streaks and every transition are logged to the system journal under
  `vpn-ethernet-failover`.

The VPN route is retained at metric 1000 during failover so interface-bound
health probes can still test that path. Link state and gateway ICMP are never
used as health evidence.

## Durable layer and Proxmox boundary

Proxmox owns and regenerates `/etc/systemd/network/eth0.network` and
`eth1.network`. This package does not edit those files. It installs separate
`*.network.d/10-vpn-ethernet-failover.conf` drop-ins, which survive regeneration
of the base files, plus an independent system service that reconciles live
route metrics.

Proxmox does not reload networkd after regenerating a running guest's files.
After any CT110 network setting changes, run the non-disruptive apply step from
the Proxmox host:

```sh
pct exec 110 -- networkctl reload
```

A full container rebuild replaces the guest root filesystem and therefore
removes the installed drop-ins, unit, and executable. The tracked copies remain
in this repo, but an administrator must rerun `apply-with-auto-revert.sh` after
a rebuild. The Proxmox `net0`/`net1` definitions, addresses, and MAC addresses
remain host-owned and are intentionally not changed by this package.

## Deployment and verification

Copy this directory to the Proxmox host, then run the guarded installer there:

```sh
scp -r system/ct110-network-failover root@192.168.68.10:/tmp/
ssh root@192.168.68.10 \
  /tmp/ct110-network-failover/apply-with-auto-revert.sh
```

The installer arms a host-side three-minute auto-revert, installs the guest
files with `pct push`, explicitly runs `networkctl reload`, and cancels the
revert only after the service, both routes, both interface-bound egress paths,
and normal VPN egress pass. Run the E2E test from the same host directory to
exercise both transitions under a separate auto-revert:

```sh
/tmp/ct110-network-failover/e2e-failover-test.sh
```

Routine inspection from CT110:

```sh
systemctl status vpn-ethernet-failover
ip -4 route show default
journalctl -u vpn-ethernet-failover
curl --interface eth1 https://connectivitycheck.gstatic.com/generate_204
```

Never change these live routes without a timed auto-revert. The apply and E2E
scripts arm host-side rollback timers before they touch CT110 networking.

## Live acceptance record - 2026-07-29

Before installation, `192.168.68.1` was proved with only a scoped
`1.1.1.1/32` route through `eth0`; `https://1.1.1.1/cdn-cgi/trace` returned the
home IP `76.170.107.235`. The scoped route was then removed. This proof and all
subsequent changes ran behind host-side timed auto-reverts.

After the non-disruptive networkd reload, live defaults were VPN metric 100 and
home metric 500. Bound HTTPS returned `193.148.16.118` on `eth1` and
`76.170.107.235` on `eth0`, while normal egress stayed on the VPN IP.

The E2E test made its pre-proved HTTPS health destination unreachable, without
dropping either link or the connected Proxmox recovery path. The journal showed
three consecutive failures, `vpn->home`, then normal traffic used `eth0` and the
home IP. A `networkctl reload` during failover temporarily reintroduced the
on-disk healthy VPN metric, and the daemon reconciled it back to home. After
restoring the destination, three consecutive successful bound probes produced
`home->vpn`; route and egress returned to `eth1` and `193.148.16.118`.
Production probe settings were restored, both auto-revert timers were inactive,
and no DNS configuration was changed.
