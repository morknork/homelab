#!/usr/bin/env bash
set -euo pipefail

WAN=ens18
IP_ALLOW=10.0.0.5

# remove our rules if present (idempotent)
iptables -D DOCKER-USER -i "$WAN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
iptables -D DOCKER-USER -i "$WAN" ! -s "$IP_ALLOW" -j DROP 2>/dev/null || true

# re-add — conntrack inserted LAST so it lands on top
iptables -I DOCKER-USER -i "$WAN" ! -s "$IP_ALLOW" -j DROP
iptables -I DOCKER-USER -i "$WAN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
