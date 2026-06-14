# Docker-User FW

## Overview

Docker forwards traffic to containers by adding rules to iptables.
Since this traffic goes through the FORWARD chain and not the INPUT chain, traffic doesn't reach ufw rules.
Script removes rule when run to ensure idempotency (ensures only 1 set of rules exists).
 - conntack RETURN rule is to ensure traffic that is initiated by containers can make it back (stateful firewall)

Service (Systemd) unit is to ensure permanency (iptables are volatile)

Systemd unit ensures script is run after docker.service
 - after= after docker.service runs (only the order)
 - requires= runs only if docker.service exists
 - partof= runs service unit if docker.service restarts
 - wantedby= runs service unit on boot

## Install Steps

1. Add script to '/usr/local/sbin/docker-user-fw.sh'
2. sudo chown root:root /usr/local/sbin/docker-user-fw.sh
3. sudo chmod 744 /usr/local/sbin/docker-user-fw.sh
4. Add service unit to '/etc/systemd/system/docker-user-fw.service'
5. sudo systemctl daemon-reload
6. sudo systemctl enable --now docker-user-fw.service 

## Verify 
Run
 - systemctl status docker-user-fw.service
 - sudo iptables -S DOCKER-USER

You should see (based on WAN & Allow IP):
-N DOCKER-USER
-A DOCKER-USER /-i ${WAN} -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER /-i ${WAN} ! -s ${Allow IP} -j DROP
-A DOCKER-USER -j RETURN
