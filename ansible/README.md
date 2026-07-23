# homelab/ansible

Configuration management for my Proxmox homelab. Goal is full destroy-and-rebuild
capability alongside Terraform and application data backups, so hardware failure loses nothing but time.

## Current state

Working:

- **Inventory** - `inventory.yml`, groups below.
- **Bootstrap** - `playbooks/bootstrap.yml` provisions the `svc-ansible` service
  account on all hosts. Run as `madmin` with `-K`.
- **Secrets** - SOPS with age. `group_vars/all/secrets.sops.yaml`, decrypted at
  runtime by the `community.sops` vars plugin.
- **site.yml**
- **base_common tasks**

## Inventory groups

| Group     | Members                     |
| --------- | --------------------------- |
| `proxmox` | the PVE host                |
| `vm`      | VM guests                   |
| `lxc`     | LXC guests                  |
| `guests`  | parent group — `vm` + `lxc` |
| `control` | the Ansible control node    |

## Access model

Two deliberate privilege paths.

**`svc-ansible`** — the automation account. Own group, locked password, SSH pubkey
auth, passwordless sudo via `/etc/sudoers.d/ansible`. Everything in `site.yml`
runs as this.

**`madmin`** — my user account, used with `-K` for `bootstrap.yml`.

`bootstrap.yml` is **permanent break-glass, not a one-shot**. The service-account
tasks also run on every normal pass as a drift enforcer, but they cannot repair
the one failure that matters most: if `svc-ansible`'s passwordless sudo is
removed, the enforcer can no longer escalate to restore it. Recovery is
`bootstrap.yml` as `madmin`. Do not delete it once hosts are provisioned.

The tasks live in exactly one file, reached by two callers:

```
roles/base_common/tasks/service_account.yml   # the tasks
  ├── imported by roles/base_common/tasks/main.yml    (normal run, as svc-ansible)
  └── reached by playbooks/bootstrap.yml via tasks_from (first touch, as madmin)
```

## Planned role map

| Role            | Targets           | Notes                                             |
| --------------- | ----------------- | ------------------------------------------------- |
| `base_common`   | `all`             | universal floor — assumes nothing about host type |
| `base_server`   | all but `control` | server baseline                                   |
| `kernel_tuning` | `vm:proxmox`      | LXCs share the host kernel, so excluded           |
| `caddy`         | `caddy`           |                                                   |
| `authentik`     | `authentik`       | pulls `docker` via meta                           |
| `arr`           | `arr`             | pulls `docker` via meta                           |
| `jellyfin`      | `jellyfin`        |                                                   |
| `adguard`       | `adguard`         |                                                   |

`docker` is **not** targeted at hosts. It is declared as a dependency in each
containerised service's `meta/main.yml`, so the requirement travels with the
service rather than relying on remembering to list it per play.

## Conventions

**Variables.** Tunables go in a role's `defaults/main.yml` — lowest precedence, so
`group_vars` and `host_vars` can override them.

**Playbooks stay thin** — `site.yml` and `bootstrap.yml` only. Targeting logic
belongs in plays inside `site.yml`, sliced with `--limit` / `--tags`.

**Task granularity.** Cleanup and maintenance get their own tasks rather than
being bolted onto an install task, so a `changed` result stays attributable. The
drift enforcer is only worth having if a green run genuinely means nothing moved.

## Secrets

SOPS with age. Private keys live in `~/.config/sops/age/keys.txt` on the control
node — one file, multiple identities, one per line.
Recipients are set per-repo by `.sops.yaml` creation rules.

Edit with `sops edit group_vars/all/secrets.sops.yaml`.

`ansible.cfg` needs **both** plugins listed:

```ini
vars_plugins_enabled = host_group_vars, community.sops.sops
```

Naming only the SOPS plugin silently disables normal `group_vars` loading.

## Roadmap

1. ~~`site.yml` wiring the role map above to inventory groups.~~
2. ~~`base_common` proper — timezone, baseline packages, service account.~~
3. `base_server`, `kernel_tuning`.
4. Per-service roles, converting existing hand-managed config.
5. Patching as a separate play
6. Terraform provisioning
7. Timed full rebuild drill.

Patching must stay out of `base_common`. Roles converge to a state _I_ define and
should be boring to re-run; patching converges to a moving target defined
upstream. Mixing them means `site.yml` is no longer safe to run casually.

**Reboots.** Not yet designed. Kernel and libc upgrades need a restart
(`/var/run/reboot-required`). Needs an ordering and batching model — `serial:`
— so the fleet doesn't restart at once, and the PVE host handled separately since
its reboot takes every guest with it.

**`update_password` for `madmin`.** Enforce the hash every run, or only at account
creation. Matters because the account already exists fleet-wide.

## Learned Lessons

- Host patterns that match zero hosts skip **silently green**. A typo'd group
  name looks like a successful run that did nothing.
- Split tasks if the outcome (ok, changed) is a useful metric.
  - e.g. Adding packages and clearing apt cache
