# Architecture: how the pieces connect

This describes the Forgejo + Authentik stack as it is built in this directory. The original design is in [PLAN.md](PLAN.md).

## Components

| Component | Where it runs | Purpose |
|---|---|---|
| Proxmox VE | `192.168.1.23` (host) | Hypervisor. Hosts the three VMs. API on `:8006`. |
| `forgejo` VM | `192.168.1.50` | Forgejo server, its Postgres, and Caddy TLS front end. |
| `authentik` VM | `192.168.1.51` | Authentik server and worker, its Postgres, and Caddy TLS front end. |
| `runner-01` VM | `192.168.1.52` | Forgejo Actions runner. Runs jobs in Docker containers. |
| Client machines | LAN | Browsers and `git` clients. Trust the internal CA. |
| Router or Pi-hole | LAN DNS | Resolves `git.home.lab` and `auth.home.lab` to the VMs. |

## Network diagram

```
                       LAN 192.168.1.0/24
  ┌──────────┐   DNS: git.home.lab -> .50, auth.home.lab -> .51
  │  Client  │──────────────────────────────────────────────────────────┐
  │ browser  │                                                          │
  │ git/ssh  │                                                          │
  └────┬─────┘                                                          │
       │ HTTPS 443         SSH 2222                                     │
       ▼                   ▼                                            │
 ┌─────────────────────────────────────┐        HTTPS 443 (SSO login)    │
 │ forgejo VM  192.168.1.50            │◄────────────────────────────────┤
 │  caddy :443 ──► forgejo :3000       │                                 │
 │  forgejo :2222 (SSH git)            │                                 │
 │  forgejo ──► postgresql (forgejo)   │                                 │
 │  forgejo ──OIDC discovery/token──►  │─────────┐                       │
 └──────────────▲──────────────────────┘         │ HTTPS 443 (server side)│
                │ HTTPS 443 (register runner)    ▼                       │
                │                 ┌─────────────────────────────────┐    │
                │                 │ authentik VM  192.168.1.51      │◄───┘
                │                 │  caddy :443 ──► server :9000    │
                │                 │  server + worker ──► postgres   │
                │                 │  worker loads blueprint         │
                │                 └─────────────────────────────────┘
 ┌──────────────┴──────────────────────┐
 │ runner-01 VM  192.168.1.52          │
 │  forgejo-runner (daemon)            │
 │   ├─ polls git.home.lab for jobs    │
 │   └─ docker.sock ──► job containers │
 └─────────────────────────────────────┘
```

## Ports

| Host | Port | Exposed to | Used for |
|---|---|---|---|
| forgejo | 80, 443 | LAN | Caddy: HTTP redirect and Forgejo web UI |
| forgejo | 2222 | LAN | Forgejo SSH for `git` (host port maps to container 2222) |
| forgejo | 127.0.0.1:3000 | localhost only | Forgejo HTTP, used by Ansible health checks |
| authentik | 80, 443 | LAN | Caddy: Authentik UI and OIDC endpoints |
| authentik | 127.0.0.1:9000 | localhost only | Authentik HTTP, used by Ansible health checks |
| runner-01 | none | n/a | Runner is outbound-only (polls Forgejo) |
| proxmox | 8006 | Admin LAN | API used by Terraform |

Ports 22 on every VM is for admin SSH. UFW default is deny inbound. Only the ports listed in `host_firewall` (`ansible/group_vars/all/main.yml`) are opened.

## Name resolution

Three layers have to agree on the names:

1. **LAN DNS** (router or Pi-hole): `git.home.lab` to `192.168.1.50`, `auth.home.lab` to `192.168.1.51`. Needed by client machines and by the VMs.
2. **VM `/etc/hosts`**: set by the Ansible `common` role on every VM, so the VMs resolve the names even if DNS is down.
3. **Container `extra_hosts`**: Docker containers do not read the host's `/etc/hosts`, so the compose files add explicit entries:
   - Forgejo container: `auth.home.lab` to `192.168.1.51`, so it can reach Authentik for OIDC.
   - Runner container: `git.home.lab` to `192.168.1.50`, and `auth.home.lab` to `192.168.1.51`.

## TLS and the internal CA

Each TLS front end is Caddy with `tls internal`. Caddy creates its own root CA on first start and issues leaf certificates from it. There are two independent CAs, one per Caddy instance.

Trust is distributed in three steps:

1. **Export.** After each app stack is up, the Ansible `trust` role (`tasks/export.yml`) reads the root certificate from inside the Caddy container (`/data/caddy/pki/authorities/local/root.crt`) and stores it on the controller at `ansible/.artifacts/roots/<host>.crt`.
2. **Bundle.** The `trust` role concatenates every exported root into `ansible/.artifacts/home-lab-roots.pem`, copies it to each VM, and builds `/opt/trust/ca-bundle.pem` = system CAs + home-lab roots.
3. **Consume.** The bundle is mounted read-only into the containers that make server-side HTTPS calls:
   - Forgejo container: `/etc/ssl/certs/ca-bundle.pem`, with `SSL_CERT_FILE` set. Needed for the OIDC discovery and token calls to Authentik.
   - Runner container: same mount and env var. Needed to talk to `git.home.lab`.
   - Job containers: the runner's `container.options` mounts the bundle at `/etc/ssl/certs/ca-certificates.crt`, so `git clone` inside jobs works.

Browsers and `git` on client machines need the same roots imported into their trust store (RUNBOOK Step 8).

The export order matters. The Authentik root is exported before Forgejo starts, and the Forgejo root before the runner starts. Play order in `site.yml` enforces this.

## Identity flow (SSO login to Forgejo)

Authentik is the source of identity. Forgejo is an OIDC relying party.

```
 Browser            Forgejo (git.home.lab)                 Authentik (auth.home.lab)
    │  1. GET /        │                                          │
    │─────────────────►│                                          │
    │  2. "Sign in with authentik" link                           │
    │◄─────────────────│                                          │
    │  3. redirect to /application/o/authorize?client_id=forgejo  │
    │────────────────────────────────────────────────────────────►│
    │  4. login + consent (implicit consent flow)                 │
    │◄────────────────────────────────────────────────────────────│
    │  5. redirect to git.home.lab/user/oauth2/authentik/callback?code=...
    │─────────────────►│                                          │
    │                  │ 6. server-side: POST /token (code)       │
    │                  │─────────────────────────────────────────►│
    │                  │ 7. id_token + access_token               │
    │                  │◄─────────────────────────────────────────│
    │                  │ 8. GET /userinfo  (claims incl. groups)  │
    │                  │─────────────────────────────────────────►│
    │  9. session cookie; user created or linked; admin if in forgejo-admins
    │◄─────────────────│                                          │
```

Steps 6 and 8 are server-to-server. They are why the Forgejo container needs the trust bundle and the `auth.home.lab` `extra_hosts` entry.

### Groups

- The Authentik blueprint defines two groups: `forgejo-admins` and `forgejo-users`.
- A custom scope mapping adds a `groups` claim with the user's group names.
- Forgejo's OIDC source is created with `--group-claim-name groups --admin-group forgejo-admins`. Members of `forgejo-admins` become Forgejo site admins at login.
- Access to the Forgejo app inside Authentik is not yet bound to `forgejo-users`. Right now every Authentik user who can log in can reach the app. This is a known gap; add a policy binding before inviting people.

## Where each piece is defined

| Concern | File |
|---|---|
| Host prep (ops user, SSH hardening, API token, storage content) | `bootstrap/bootstrap-proxmox.sh` (run ON the Proxmox host) |
| VM sizes, IDs, static IPs | `terraform/main.tf` (`locals.vms`) |
| Terraform provider and variables | `terraform/versions.tf`, `terraform/variables.tf` |
| Host IPs used by Ansible | `ansible/inventory.ini` (must match `terraform/main.tf`) |
| Shared vars: domains, versions, firewall, `/etc/hosts` | `ansible/group_vars/all/main.yml` |
| Secrets (encrypted) | `ansible/group_vars/all/vault.yml` (from `vault.yml.example`) |
| Play order and role mapping | `ansible/site.yml` |
| Base packages, UFW, hosts entries | `ansible/roles/common/tasks/main.yml` |
| Docker Engine and Compose plugin | `ansible/roles/docker/tasks/main.yml` |
| CA export and bundle build | `ansible/roles/trust/tasks/{main,export}.yml` |
| Authentik stack and health waits | `ansible/roles/authentik/` (compose, env, Caddyfile, blueprint) |
| Forgejo stack and OIDC source | `ansible/roles/forgejo/` (compose, env, Caddyfile) |
| Runner stack and registration | `ansible/roles/forgejo_runner/` (compose, env, config) |
| Nightly backups | `ansible/roles/backup/` (script and cron) |

## Deployment order

Each arrow is a dependency. Earlier steps must succeed first.

```
1. bootstrap-proxmox.sh          ops user key, Terraform user + privsep API token, import+snippets content
        │
2. terraform apply               3 VMs with static IPs and the admin user
        │
3. ansible: common + docker      all VMs: packages, UFW, hosts, Docker
        │
4. ansible: authentik            caddy root exported ──► .artifacts/roots/authentik.crt
        │                        blueprint applied ──► OIDC app "forgejo" exists
        │
5. ansible: forgejo              bundle includes authentik root
        │                        add-oauth points at auth.home.lab discovery URL
        │                        caddy root exported ──► .artifacts/roots/forgejo.crt
        │
6. ansible: forgejo_runner       bundle includes forgejo + authentik roots
        │                        generate token on forgejo ──► register runner
        │
7. Clients: import roots into the trust store, DNS for git/auth, log in, smoke test
```

Step 4 waits for the OIDC discovery document to return. Step 5 depends on that. If the blueprint is slow to load, the wait retries for about five minutes.

## Secrets

| Secret | Where it lives | Used by |
|---|---|---|
| Proxmox root password | Set in the Proxmox UI with TOTP. Not used by any script. | Console or UI login (break-glass) |
| Proxmox `ops` SSH key | Public key in `/home/ops/.ssh/authorized_keys` on the host. Private key stays on the controller. | SSH to the Proxmox host |
| Terraform API token | Shell env var `TF_VAR_pm_api_token`. Never written to a file. Token has `privsep=1` and its own ACL. | Terraform to Proxmox API |
| Vault password | `ansible/.vault_pass` (gitignored) | Decrypts `vault.yml` |
| Vault contents | `ansible/group_vars/all/vault.yml` (encrypted, safe to commit) | DB passwords, Authentik secret and bootstrap values, OIDC client secret |
| Authentik `.env` and Forgejo `.env` | On the VMs at `/opt/<app>/.env`, mode 0600 | Compose interpolation |
| Forgejo runner token | Generated on demand, used once to register, then stored in the runner's `.runner` file | Runner registration |
| Caddy root CAs | `ansible/.artifacts/roots/` (gitignored) | Trust bundle |
| Backups | `/var/backups/<app>/` on each VM, mode 0700 (contains `.env`) | Restore |

The OIDC client secret appears in three places that must match: the vault, the Authentik blueprint (via `FORGEJO_OIDC_CLIENT_SECRET` env on the Authentik containers), and the Forgejo `add-oauth` call.

## Data and persistence

| VM | Path | Contents |
|---|---|---|
| forgejo | `/opt/forgejo/data` | Repos, LFS, attachments, Forgejo config |
| forgejo | `/opt/forgejo/postgres` | Forgejo database |
| forgejo | `/opt/forgejo/caddy-data` | Caddy root CA and leaf certs (keep, or clients must re-trust) |
| authentik | `/opt/authentik/data` | Media, file storage |
| authentik | `/opt/authentik/postgres` | Authentik database |
| authentik | `/opt/authentik/caddy-data` | Caddy root CA (keep) |
| runner-01 | `/opt/forgejo-runner/data` | `.runner` registration file and config |

## Known limitations

- **Runner isolation.** Job containers reach the host Docker daemon through the mounted socket. A workflow can start privileged containers on the runner VM. Treat the runner as trusted-code-only until DinD or rootless is in place.
- **Docker and UFW.** Docker publishes ports by writing iptables rules that bypass UFW. The only published ports are the ones listed above, but do not assume UFW blocks a container port you add later.
- **Two Caddy CAs.** Each VM has its own root. Re-running Ansible does not rotate them, but deleting a Caddy data directory creates a new root and breaks trust until the bundle is rebuilt and clients re-import.
- **Backups stay on the VM.** The nightly dumps are on the same VM as the data. Copy them off-box, or the backup does not protect against losing the VM.
- **No app-level access control yet.** See Groups above.
- **Unverified on live host.** Compose files parse, and `terraform validate` and `ansible-playbook --syntax-check` pass. Nothing has run against the real Proxmox host yet.

## Adding the platform API later

- Create a new Authentik OAuth2 provider and application (copy the Forgejo blueprint entries, change the name, slug, redirect URI).
- Give the platform API its own VM, or add a compose stack alongside the existing ones.
- Reuse the same CA bundle mechanism if the API needs to call Forgejo or Authentik over HTTPS.
