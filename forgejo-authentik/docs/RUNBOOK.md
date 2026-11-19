# Runbook: Forgejo + Authentik on Proxmox

Every step to go from a bare Proxmox host to a working Forgejo, Authentik, and runner stack. Use this document in order. Steps are marked with where they run:

- **[PVE host]**: Proxmox host at `192.168.1.23`, run as root from the web UI (node > Shell) or the physical console. Only Step 1 and Step 2 use this.
- **[Controller]**: the Linux machine you run Terraform and Ansible from. It must reach `192.168.1.23` and the VM IPs. Everything after Step 2 runs here.

Design background is in [ARCHITECTURE.md](ARCHITECTURE.md). The approved plan and deviations are in [PLAN.md](PLAN.md).

## Addresses and names

| Thing | Value |
|---|---|
| Proxmox host (API and UI) | `192.168.1.23:8006` |
| Proxmox admin SSH user | `ops` (key-only, passwordless sudo) |
| forgejo VM | `192.168.1.50`, name `forgejo` |
| authentik VM | `192.168.1.51`, name `authentik` |
| runner VM | `192.168.1.52`, name `runner-01` |
| VM admin user (Terraform cloud-init) | `devops` (key-only) |
| Forgejo URL | `https://git.home.lab` |
| Authentik URL | `https://auth.home.lab` |
| Forgejo SSH | `ssh://git@git.home.lab:2222` |

These IPs and names must match in `terraform/main.tf`, `ansible/inventory.ini`, and `ansible/group_vars/all/main.yml`.

---

## Step 0. Prepare the controller [Controller]

This section assumes Ubuntu 22.04 or 24.04.

Base packages:

```bash
sudo apt update
sudo apt install -y git openssh-client openssl gnupg wget unzip pipx
pipx ensurepath && export PATH="$HOME/.local/bin:$PATH"
```

Terraform, from the HashiCorp apt repository:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform version    # must be 1.6 or newer
```

Ansible, via pipx. The Ubuntu `ansible` package is too old for this repo:

```bash
pipx install --include-deps ansible-core
ansible-playbook --version    # must be ansible-core 2.16 or newer
```

`community.general` is installed in Step 6.

Get the repo:

```bash
git clone <your-repo-url> homeops
cd homeops/forgejo-authentik
```

Create an SSH key if you don't have one:

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "homeops-controller"
chmod 600 ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub     # you need this line in Step 1
```

Use `~/.ssh/id_ed25519` if you already have it. It is the path that Terraform cloud-init and Ansible both read.

---

## Step 1. Bootstrap the Proxmox host [PVE host]

This is the only step that needs the root password, and only once, through the web UI or console. It creates the `ops` admin user, locks down SSH, creates the Terraform API user and token, and enables the storage types needed for cloud-image imports.

1. On the controller, copy the bootstrap script:
   ```bash
   cat bootstrap/bootstrap-proxmox.sh
   ```
2. In the Proxmox web UI, open the node (`pve`) > **Shell**. Log in as `root@pam`.
3. Paste the contents of `bootstrap-proxmox.sh` into the Shell. For example, save it as `/root/bootstrap-proxmox.sh` with `cat > /root/bootstrap-proxmox.sh`, then paste and end with Ctrl-D.
4. Run it with your public key line from Step 0:
   ```bash
   OPS_PUBKEY="ssh-ed25519 AAAA... you@controller" bash /root/bootstrap-proxmox.sh
   ```
5. **Save the printed token secret.** It is shown only once. Format: `terraform@pve!tf=<secret>`.
6. **Keep this Shell or console session open** until Step 2 succeeds. The script disables password SSH, so a wrong key would lock you out.

What the script does, for reference:

- Creates `ops` with `/home/ops/.ssh/authorized_keys` and `NOPASSWD` sudo through `/etc/sudoers.d/90-ops`.
- Writes `/etc/ssh/sshd_config.d/90-homeops.conf`: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`.
- Creates `terraform@pve`, role `TerraformProv`, and token `tf` with `--privsep 1` and its own ACL.
- Sets storage `local` to content types `iso,vztmpl,backup,import,snippets`.

If you already created the old `terraform@pve!tf` token from an earlier run, remove it first (`pveum user token remove terraform@pve tf`), then run the script again to get a new secret.

## Step 2. Verify key-only access [Controller]

```bash
ssh ops@192.168.1.23 'whoami && sudo -n true && echo sudo-ok'
ssh -o PasswordAuthentication=no -o PreferredAuthentications=password root@192.168.1.23 true   # must FAIL
```

The first command must print `ops`, then `sudo-ok`. The second must be refused. Only close the Step 1 session after the first command works.

## Step 3. Secure the root account [PVE host or web UI]

Root's password is still set from the installer. Keep it as break-glass only.

1. Web UI > **Datacenter > Permissions > Users > root@pam > Edit** and set a long, unique password.
2. Same page: **TOTP > Add > TOTP** and scan with an authenticator app. Save the recovery codes somewhere safe.

Do not put the root password in any file or script.

---

## Step 4. Provision the VMs with Terraform [Controller]

1. Export the API token into the current shell (not into a file):
   ```bash
   export TF_VAR_pm_api_token='terraform@pve!tf=<secret from Step 1>'
   ```
2. Create the variable file (gitignored):
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Adjust `node_name` (default `pve`), `image_datastore`, `vm_datastore`, `bridge`, `gateway`, and `dns_servers` to match your host. Check with `pvesh get /nodes` and `pvesm status` on the Proxmox host.
3. Provision:
   ```bash
   terraform init
   terraform validate
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
4. Wait about a minute for cloud-init, then check reachability:
   ```bash
   for ip in 192.168.1.50 192.168.1.51 192.168.1.52; do ssh -o StrictHostKeyChecking=accept-new devops@$ip 'hostname && uptime -p'; done
   ```

**Check sudo for the `devops` user before Step 7.** The bpg provider's `user_account` block does not expose a sudo setting, so `devops` might not have passwordless sudo. Ansible needs it to become root.

```bash
ssh devops@192.168.1.50 'sudo -n true && echo sudo-ok'
```

If this prints a password prompt or an error, switch the admin user to Debian's default cloud user, which has sudo. Set `admin_user = "debian"` in `terraform.tfvars`, change `ansible_user: devops` to `debian` in `ansible/inventory.ini`, then run `terraform apply` again. Do not skip this check.

---

## Step 5. DNS [Controller and clients]

Point these names at the VMs. Use your router or Pi-hole, or a hosts file on each client.

```
192.168.1.50  git.home.lab
192.168.1.51  auth.home.lab
```

The Ansible `common` role also writes these entries into each VM's `/etc/hosts`, so the VMs don't depend on DNS.

---

## Step 6. Secrets and collections [Controller]

1. Install the Ansible collection:
   ```bash
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   ```
2. Create the vault password file. Keep it out of git:
   ```bash
   read -rs -p "Vault password: " VP && echo && printf '%s' "$VP" > .vault_pass && chmod 600 .vault_pass && unset VP
   ```
3. Create the vault from the example:
   ```bash
   cp group_vars/all/vault.yml.example group_vars/all/vault.yml
   ```
   Replace every `CHANGE_ME`. Generate the Authentik secret key with:
   ```bash
   openssl rand -base64 60 | tr -d '\n'; echo
   ```
   Generate the other passwords the same way, for example `openssl rand -hex 24`. Use a different value for each.
4. Encrypt the vault:
   ```bash
   ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass
   ```

The encrypted `vault.yml` is safe to commit. `.vault_pass` is not, and it is in `.gitignore`.

If your key has a passphrase, load it into the agent first. Ansible uses the agent to reach the VMs:

```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
```

Run that in the same shell where you run `ansible-playbook`.

---

## Step 7. Configure the stack [Controller]

```bash
cd ansible
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --vault-password-file .vault_pass --check --diff   # dry run, optional
ansible-playbook site.yml --vault-password-file .vault_pass
```

The playbook runs in this order:

1. `common` and `docker` on all VMs: packages, UFW (deny inbound, plus SSH and the service ports), `/etc/hosts`, and Docker Engine with the Compose plugin.
2. `trust` and `authentik` on the authentik VM: Authentik server, worker, Postgres, Caddy, and the Forgejo SSO blueprint. Waits for Authentik to be ready and for the OIDC discovery document. Exports Caddy's root CA to `ansible/.artifacts/roots/authentik.crt`.
3. `trust` and `forgejo` on the forgejo VM: Forgejo, Postgres, Caddy. Registers Authentik as the OIDC login source. Exports `forgejo.crt`.
4. `trust` and `forgejo_runner` on the runner VM: builds the CA bundle, generates a runner token on Forgejo, registers the runner, and starts it.
5. `backup` on the authentik and forgejo VMs: nightly `pg_dump` and data tarball, cron at 02:30.

The `trust` role builds `/opt/trust/ca-bundle.pem` on each VM from the system CAs and the exported Caddy roots. Forgejo, the runner, and job containers all read it.

If the run fails partway, fix the cause and run the same command again. The roles are idempotent.

---

## Step 8. Trust the internal CA on your clients [Clients]

Browsers and `git` on your client machines need the two Caddy roots, or they show certificate warnings. Copy these files from `ansible/.artifacts/roots/` on the controller:

- `forgejo.crt`
- `authentik.crt`

**Linux (Debian/Ubuntu):**

```bash
sudo cp forgejo.crt authentik.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**Windows:** double-click each `.crt`, choose **Local Machine**, then **Place all certificates in the following store** > **Trusted Root Certification Authorities**.

**macOS:** double-click each `.crt` to open Keychain Access, then set the certificate to **Always Trust**. Or use `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <file>`.

Firefox keeps its own trust store. Import the certs in Firefox settings under **Certificates** if needed.

---

## Step 9. Verify [Clients]

1. **Authentik:** open `https://auth.home.lab`, log in as `akadmin` with the bootstrap password from the vault. Check that the `forgejo-admins` and `forgejo-users` groups exist. Add your users to the right group.
2. **Forgejo:** open `https://git.home.lab`. You should see the "Sign in with authentik" option. Log in through Authentik. If your user is in `forgejo-admins`, you become a site admin.
3. **Git over SSH:**
   ```bash
   ssh -p 2222 git@git.home.lab
   git clone ssh://git@git.home.lab:2222/<owner>/<repo>.git
   ```
4. **Actions:** create a repo with `.forgejo/workflows/test.yml` containing a job with `runs-on: ubuntu-latest` and a `run: echo ok` step. Check that the job runs on `runner-01`.
5. **Runner registration:** in Forgejo, check **Site Administration > Actions > Runners**. `runner-01` should be listed as online.

---

## Step 10. Off-box backups [Controller or NAS]

Backups run nightly on each VM into `/var/backups/<app>/`, with mode 0700 on the directory and 0600 on the files. They contain `.env` secrets, so store copies only on encrypted or access-controlled storage.

Copy these off the VMs on a schedule you choose:

- `/var/backups/forgejo/`
- `/var/backups/authentik/`

Also enable Proxmox backups (`vzdump`) for the three VMs in **Datacenter > Backup**. The backup retention is 14 days by default (`backup_retention_days`).

---

## Operations

### Rotate the Terraform API token

On the Proxmox host (Step 1 shell, or SSH as `ops` with `sudo`):

```bash
sudo pveum user token remove terraform@pve tf
sudo bash /root/bootstrap-proxmox.sh   # with OPS_PUBKEY set; creates a new token and prints it once
```

Update `TF_VAR_pm_api_token` on the controller.

### Re-run Terraform after a change

```bash
export TF_VAR_pm_api_token='terraform@pve!tf=<secret>'
cd terraform && terraform plan && terraform apply
```

### Re-run Ansible after a change

```bash
cd ansible && ansible-playbook site.yml --vault-password-file .vault_pass
```

### Re-register the runner

Only needed if the runner was deleted in Forgejo or its registration is broken:

```bash
ssh devops@192.168.1.52 'sudo rm -f /opt/forgejo-runner/data/.runner'
cd ansible && ansible-playbook site.yml --vault-password-file .vault_pass --limit runner-01
```

### Rotate the OIDC client secret

Change `vault_forgejo_oidc_client_secret` in the vault, then run the full playbook. The blueprint updates the Authentik provider on the worker's next blueprint pass. The Forgejo add-oauth step only runs when the `authentik` source is missing, so it will not pick up the new secret by itself. In Forgejo, go to **Site Administration > Authentication Sources**, edit the `authentik` source, and paste the new client secret. Verify login afterwards.

### Rebuild a Caddy root (only when necessary)

Deleting a Caddy data directory creates a new root CA. Every client must re-import the new root, and the trust bundles must be rebuilt. Do this only if the root is compromised or lost.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `terraform apply` fails with 403 on storage or import | The storage content types are not set. Run `pvesm set local --content iso,vztmpl,backup,import,snippets` on the host. |
| `terraform` cannot connect to the API | Check the endpoint port `8006` and `pm_insecure = true` for the self-signed cert. Check the token value. |
| VM is created but SSH fails | cloud-init may still be running. Wait 1-2 minutes. Check the console in the UI. |
| Ansible says "Missing sudo password" | The `devops` user has no passwordless sudo. See the check in Step 4. |
| Browser shows a certificate warning | The Caddy root is not trusted on that client. See Step 8. |
| Forgejo login via Authentik fails with a TLS error | The Forgejo container does not trust the Authentik root. Check `/opt/trust/ca-bundle.pem` on the forgejo VM and that `authentik.crt` was exported. Re-run the playbook. |
| Forgejo login fails with "invalid client" | `vault_forgejo_oidc_client_secret` differs between the blueprint and the add-oauth source. Re-run after fixing the vault. |
| Runner job fails on `git clone` with a TLS error | The job container does not trust the bundle. Check the `container.options` in `/opt/forgejo-runner/data/config.yml`. |
| Blueprint does not appear in Authentik | Check the worker logs: `docker compose -f /opt/authentik/compose.yml logs worker`. Blueprint discovery can take a few minutes. |
| Ports look open despite UFW | Docker publishes ports through its own iptables rules, which bypass UFW. Only the ports in the `host_firewall` list should be published. |

Logs for each stack are in its compose directory:

```bash
cd /opt/forgejo && docker compose logs -f forgejo
cd /opt/authentik && docker compose logs -f server worker
cd /opt/forgejo-runner && docker compose logs -f runner
```

---

## Security notes

- The `ops` user has passwordless sudo. Anyone with its private key has root on the Proxmox host. Protect that key.
- Root on Proxmox is key-only for SSH and password-protected with TOTP in the UI. Root's password is used for UI break-glass only.
- The Terraform API token has `privsep=1` and only the `TerraformProv` privileges. It is never written to a file.
- The runner mounts the host Docker socket. Jobs can control the runner VM's Docker daemon. Run only trusted workflows on it until a DinD or rootless runner is in place.
- The vault password and the Authentik bootstrap password should be rotated after first login.
- The Authentik `akadmin` bootstrap account is for setup only. Create named admin accounts and disable the bootstrap user afterwards.
