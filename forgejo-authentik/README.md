# Forgejo + Authentik on Proxmox

Provisions the identity and source-control base for the homelab:

- **Forgejo** (git, Actions, governance) on `git.home.lab`
- **Authentik** (IdP, SSO for Forgejo) on `auth.home.lab`
- **Forgejo runner** VM for Actions jobs

**Start here: [docs/RUNBOOK.md](docs/RUNBOOK.md)** has every step in order, with where each one runs (Proxmox host, controller, or client).

Docs:

- [docs/RUNBOOK.md](docs/RUNBOOK.md): step-by-step setup, operations, and troubleshooting
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the VMs, DNS, TLS trust, SSO flow, and secrets connect
- [docs/PLAN.md](docs/PLAN.md): the approved plan and what changed during the build

Proxmox VE host: `192.168.1.23`. The API answers on `:8006`. No root password is used after the first setup. Access is by SSH key (`ops` user) and a privilege-separated API token for Terraform.

Layout:

```
forgejo-authentik/
  bootstrap/bootstrap-proxmox.sh   one-time host prep, run ON the Proxmox host as root
  terraform/                       3 Debian 12 VMs via bpg/proxmox (cloud-init, static IPs)
  ansible/                         common, docker, trust, authentik, forgejo, forgejo_runner, backup
  docs/                            RUNBOOK, ARCHITECTURE, PLAN
```

| VM        | IP            | vCPU/RAM/Disk | Role                                       |
|-----------|---------------|---------------|--------------------------------------------|
| forgejo   | 192.168.1.50  | 2 / 4G / 40G  | Forgejo + Postgres + Caddy                 |
| authentik | 192.168.1.51  | 2 / 4G / 30G  | Authentik server/worker + Postgres + Caddy |
| runner-01 | 192.168.1.52  | 4 / 8G / 60G  | Forgejo Actions runner (Docker)            |

Adjust IPs in both `terraform/main.tf` and `ansible/inventory.ini` if your LAN differs.

## Quick order

1. Bootstrap the Proxmox host (`bootstrap/bootstrap-proxmox.sh`, run on the host). See RUNBOOK Step 1.
2. Provision the VMs with Terraform from the controller. RUNBOOK Step 4.
3. Set up the vault and secrets. RUNBOOK Step 6.
4. Configure the stack with Ansible. RUNBOOK Step 7.
5. Trust the internal CA on your clients and verify. RUNBOOK Steps 8 and 9.

## Operational notes

- Authentik and Forgejo versions are pinned in `ansible/group_vars/all/main.yml`. Check release notes before bumping (Forgejo LTS 15 is supported until July 2027).
- Backups: nightly `pg_dump` + data tarball in `/var/backups/<app>` on each VM (contains `.env`, so it is `0600`). Copy these off-box. Proxmox `vzdump` is a good second layer.
- Docker publishes ports past UFW. Only ports 80/443/2222 are published by design; keep Proxmox and VMs off the internet.
- Job containers mount the CA bundle, but jobs that call external services over HTTPS need their own CA handling.
- Governance (branch protection, required reviews, CODEOWNERS, org/team structure) is a Forgejo configuration phase after the base is up. It's not in the Ansible yet.
- The platform API and k3s are deferred; they can attach to the same Authentik as an OIDC client later.

## Not yet verified

This scaffold was written without running it against the host. Run `terraform validate`, `ansible-playbook --syntax-check`, and a dry run before the first apply. The Forgejo runner image tag, the `forgejo-cli generate-runner-token` output format, and whether the `devops` VM user has passwordless sudo are the most likely things to need adjusting on first run. RUNBOOK Step 4 has the sudo check.
