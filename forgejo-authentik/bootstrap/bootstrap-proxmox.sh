#!/usr/bin/env bash
# One-time Proxmox VE host preparation for the Forgejo/Authentik stack.
#
# Run this ON THE PROXMOX HOST as root, from the web UI (node > Shell) or the
# physical console. Do not run it over SSH with the root password.
# Copy this file to the host, or paste it into the Shell.
#
#   OPS_PUBKEY="ssh-ed25519 AAAA... you@mac" bash bootstrap-proxmox.sh
#
# What it does (idempotent, safe to re-run):
#   1. Creates a key-only Linux admin user (default: ops) with passwordless sudo.
#   2. Disables password SSH logins and root password logins (root stays key-only).
#   3. Creates the terraform@pve user, a least-privilege role, and a
#      privilege-separated API token (privsep=1) with its own ACL.
#   4. Enables the storage content types needed for cloud-image imports.
#
# It does NOT set or print any password. Set a strong root password and TOTP in
# the UI yourself (Datacenter > Permissions > Users > root@pam > TOTP).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root on the Proxmox host." >&2; exit 1; }
: "${OPS_PUBKEY:?Set OPS_PUBKEY to your SSH public key line (ssh-ed25519 AAAA...)}"

OPS_USER="${OPS_USER:-ops}"
STORAGE="${PVE_STORAGE:-local}"
TOKEN_ID="tf"
TF_USER="terraform@pve"
TF_ROLE="TerraformProv"
TF_PRIVS="Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"

echo ">> 1. Admin user '${OPS_USER}' (key-only)"
id "$OPS_USER" &>/dev/null || useradd -m -s /bin/bash -G sudo "$OPS_USER"
passwd -l "$OPS_USER" >/dev/null
install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "/home/${OPS_USER}/.ssh"
AUTH="/home/${OPS_USER}/.ssh/authorized_keys"
touch "$AUTH"
grep -qxF "$OPS_PUBKEY" "$AUTH" || echo "$OPS_PUBKEY" >> "$AUTH"
chown "$OPS_USER:$OPS_USER" "$AUTH"
chmod 600 "$AUTH"
echo "${OPS_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/90-${OPS_USER}"
chmod 440 "/etc/sudoers.d/90-${OPS_USER}"
visudo -cf "/etc/sudoers.d/90-${OPS_USER}" >/dev/null

echo ">> 2. SSH: keys only, root key-only"
cat > /etc/ssh/sshd_config.d/90-homeops.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd
echo "   Keep this session open and verify 'ssh ${OPS_USER}@<host>' from the controller before closing it."

echo ">> 3. Terraform user, role, ACL, and privsep API token"
pveum role add "$TF_ROLE" -privs "$TF_PRIVS" 2>/dev/null || pveum role modify "$TF_ROLE" -privs "$TF_PRIVS"
pveum user add "$TF_USER" --comment "Terraform provisioning" 2>/dev/null || true
pveum aclmod / -user "$TF_USER" -role "$TF_ROLE"
if pveum user token list "$TF_USER" --output-format json 2>/dev/null | grep -q "\"tokenid\" *: *\"${TOKEN_ID}\""; then
  echo "   Token ${TF_USER}!${TOKEN_ID} already exists. Its secret cannot be shown again."
  echo "   To rotate: pveum user token remove ${TF_USER} ${TOKEN_ID}, then re-run this script."
else
  pveum user token add "$TF_USER" "$TOKEN_ID" --privsep 1 --comment "terraform" --output-format json
  pveum aclmod / -token "${TF_USER}!${TOKEN_ID}" -role "$TF_ROLE"
  echo "   Token secret is shown ONCE above. Store it in your shell env, not in a file:"
  echo "     export TF_VAR_pm_api_token='${TF_USER}!${TOKEN_ID}=<secret>'"
fi

echo ">> 4. Storage content for cloud-image imports"
pvesm set "$STORAGE" --content iso,vztmpl,backup,import,snippets

echo
echo "Done. Next, on the controller: cd terraform && terraform init && terraform plan"
