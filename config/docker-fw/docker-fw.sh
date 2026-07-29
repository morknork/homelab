#!/usr/bin/env bash
set -euo pipefail

CHAIN=DOCKER-FW
UPLINK=ens18
ALLOWED_IPS=(10.0.0.5)

if ! ip link show "$UPLINK" >/dev/null 2>&1; then
    echo "interface $UPLINK not found — refusing to apply a partial ruleset" >&2
    exit 1
fi
# Create new chain if it doesn't exist
iptables -N $CHAIN 2>/dev/null || true
# Flush chain before adding new ruleset
iptables -F $CHAIN

# Building entries how the packet sees them
# Conntrack for returning traffic
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
# Add rules for all allowed IPs
for ip in "${ALLOWED_IPS[@]}"; do
    iptables -A "$CHAIN" -s "$ip" -j RETURN
done
# Default deny no matchers
iptables -A "$CHAIN" -j DROP
# Deletes any previous chains for idempotency
while iptables -D DOCKER-USER -i "$UPLINK" -j "$CHAIN" 2>/dev/null; do :; done
# Add chain to DOCKER-USER
for iface in "${UPLINKS[@]}"; do
    iptables -I DOCKER-USER -i "$iface" -j ARR-FW
done