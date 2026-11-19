# Plan: Forgejo + Authentik on Proxmox (192.168.1.23)

Terraform (bpg/proxmox) provisions separate Debian cloud-init VMs for Forgejo, Authentik, and runners. Ansible configures them with Docker Compose, Caddy internal TLS, and Authentik OIDC SSO for Forgejo.

Status: approved 2026-11-19 and implemented as a scaffold. See "As built" below for where the implementation differs from the original plan. For how the pieces connect, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Summary

New repo dir `homeops/forgejo-authentik/`, separate from the kairos and k3s content. Proxmox VE is installed; no SSH key yet; no ISOs or templates. The platform API is deferred, but the layout leaves room for an extra VM or module.

## Layout (planned)

```
forgejo-authentik/
  README.md
  bootstrap/            # one-time Proxmox host bootstrap
    bootstrap-proxmox.sh   # ssh-copy-id, create terraform@pve user/role/API token, download Debian 12 cloud image to local storage
  terraform/            # bpg/proxmox provider
    providers.tf variables.tf main.tf outputs.tf terraform.tfvars.example
    modules/vm/         # cloud-init VM from Debian cloud image
  ansible/
    inventory.ini (generated from tf outputs), group_vars/
    site.yml
    roles/ common, docker, caddy, forgejo, authentik, forgejo_runner, backup
  docs/ (architecture, DNS, runbooks, governance)
```

## VMs (static IPs on 192.168.1.0/24, to be confirmed)

- forgejo-vm: 2 vCPU / 4 GB / 40 GB. Forgejo, Postgres, Caddy. SSH on 2222 for git.
- authentik-vm: 2 vCPU / 4 GB / 30 GB. Authentik server and worker, Postgres, Redis, Caddy.
- runner-vm: 4 vCPU / 8 GB / 60 GB. forgejo-runner (Docker/DinD), isolated from the Forgejo host.
- Later: platform-api VM and k3s integration.

## Steps

1. **Bootstrap** (needs root password once): push SSH key, create Terraform API token and role, download Debian 12 genericcloud image, enable snippets storage. Check storage names (`local`, `local-lvm`) and bridge `vmbr0`.
2. **Terraform**: create 3 VMs via cloud-init (user, SSH key, static IP, qemu-guest-agent). Outputs feed the Ansible inventory.
3. **DNS**: local names `git.home.lab` and `auth.home.lab` (router/Pi-hole entries or /etc/hosts). Caddy `tls internal`. Distribute the root CA to clients, the runner, and the Forgejo/Authentik VMs (needed for OIDC server-to-server calls).
4. **Ansible common and docker roles**: hardening, ufw, unattended-upgrades, chrony.
5. **Authentik**: compose (server, worker, postgres, redis), secrets via ansible-vault, bootstrap admin token, then a blueprint or Terraform `goauthentik` provider to create the Forgejo OAuth2 provider and groups (`forgejo-admins`, `forgejo-users`).
6. **Forgejo**: compose (forgejo, postgres), `app.ini` via env (disable registration, require sign-in, Actions enabled), OIDC auth source to Authentik with group-to-admin claim mapping, org/team structure, branch protection, and a governance baseline (CODEOWNERS, required reviews, optional signed commits).
7. **Runner**: register to Forgejo (org-level token), labels (docker, ubuntu-latest), limited resources. Docker socket isolation via DinD or rootless.
8. **Backups**: nightly `forgejo dump` and pg_dump for both apps, to Proxmox vzdump plus a local or NAS target, and a Proxmox backup schedule for the VMs.
9. **Docs and runbooks**, then smoke tests.

## Verification (planned)

- `terraform validate` and `plan`, `ansible-lint`, `ansible-playbook --check`.
- `curl https://git.home.lab` and `https://auth.home.lab`. Log in to Forgejo via Authentik SSO. Git clone and push over SSH. A workflow runs on the runner. Restore test from backup.

## Risks and open items

- Proxmox root password is needed once. It is not stored; secrets go in ansible-vault and gitignored tfvars. `id_rsa` in the Proxmox directory must not be committed.
- Confirm IP range, storage names, domain (`home.lab` assumed), and RAM available on the host.
- Internal CA trust is the most common OIDC failure point.

## As built (2026-11-19)

Differences between the approved plan and the scaffold in `forgejo-authentik/`:

| Area | Plan | As built | Why / impact |
|---|---|---|---|
| Authentik data stores | Postgres + Redis | Postgres only | Authentik 2026.x runs without Redis. Fewer moving parts. |
| Terraform layout | `providers.tf`, `modules/vm/` | `versions.tf` (provider and variables) and a flat `main.tf` | Three VMs did not justify a module. |
| Ansible inventory | Generated from Terraform outputs | Static `inventory.ini`, IPs kept in sync by hand with `terraform/main.tf` | Simpler; a generator can come later. |
| Caddy | Separate `caddy` role | Caddy is a service in each app's compose stack | Each stack owns its TLS front end; no shared Docker network needed. |
| Forgejo config | `app.ini` via env | `FORGEJO__section__KEY` env vars in compose | Same effect, no file to template. |
| OIDC source | Set up by hand or by script | `forgejo admin auth add-oauth` run idempotently by Ansible | Re-runs are safe; secret kept out of logs with `no_log`. |
| Authentik OAuth app | Blueprint or Terraform `goauthentik` provider | Authentik blueprint mounted into the worker (`roles/authentik/files/forgejo-blueprint.yaml`) | No extra provider to run. Groups claim comes from a custom scope mapping. |
| Runner isolation | DinD or rootless Docker | Host Docker socket mounted into the runner container | **Weaker than planned.** Jobs can control the runner VM's Docker daemon. Accepted for the single-VM runner; revisit before running untrusted workflows. |
| Runner token | Org-level | Global runner token from `forgejo-cli actions generate-runner-token` | Works for every repo; can be scoped later with `--scope`. |
| Backups | `forgejo dump` plus vzdump and NAS | Nightly `pg_dump` and data tarball on each VM (`/var/backups/<app>`, mode 0700) | Off-box copy and vzdump schedule are still manual. |
| Proxmox access | Root over SSH via `ssh-copy-id`; Terraform token `privsep=0` | Root password used once from the UI or console, then `ops` user with key-only SSH and sudo; Terraform token `privsep=1` with its own ACL; token passed as `TF_VAR_pm_api_token` | Matches the IAM model. No root SSH password, and the token's privileges are scoped. |
| Governance | Automated baseline | Not implemented | Forgejo-side configuration phase, after the base is up. |
| Verification | `ansible-lint`, `--check`, `terraform plan` | `terraform validate` and `ansible-playbook --syntax-check` pass; compose templates render and parse as YAML | Nothing has been applied to the live host yet. |

## Open items after the scaffold

- Run `bootstrap-proxmox.sh`, then `terraform apply`, then `site.yml`, and fix whatever the first run surfaces.
- Confirm the runner image tag (`code.forgejo.org/forgejo/runner:12`) and the `generate-runner-token` output format on the live host.
- Decide the runner isolation approach (DinD or rootless) before enabling workflows from untrusted contributors.
- Add an off-box backup target and a vzdump schedule.
- Write the governance baseline: branch protection, required reviews, CODEOWNERS, org and team layout.
- Platform API and k3s integration: attach as OIDC clients of the existing Authentik.
