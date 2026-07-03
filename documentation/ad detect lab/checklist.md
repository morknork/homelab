# Detection Lab
## 1. Domain
- [x] promote server to DC (see promotion checklist)
- [x] join the Win11 client to domain
- [x] basic AD structure: users, groups, OUs
- [x] confirm client logs in with domain creds

## 2. Telemetry
- [ ] install Sysmon
- [ ] decide on config and install sysmon config
- [ ] turn on Windows audit policy (logon events, process creation, etc)
- [ ] confirm events are actually landing in the local Event Log

## 3. SIEM
- [ ] stand up Wazuh
- [ ] get the agent on the DC + client, logs flowing to the manager
- [ ] confirm Sysmon + security events show up in Wazuh
- [ ] wire in some Sigma rules

## 4. Attack sim
- [ ] install Atomic Red Team on the client
- [ ] run a few atomics (start simple, something noisy)
- [ ] confirm the activity shows up in Wazuh

## 5. Detect + tune
- [ ] check which atomics actually fired a detection
- [ ] dig into what was missed and why
- [ ] tune rules / fill gaps
- [ ] write up what each detection caught

Document each phase as you go: break/fixes, commands
