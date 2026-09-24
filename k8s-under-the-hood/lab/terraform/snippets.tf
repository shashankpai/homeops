# ==============================================================================
# Cloud-init snippet: install qemu-guest-agent on first boot
# ==============================================================================
# The bpg/proxmox provider waits for the QEMU guest agent to publish network
# interfaces when `agent { enabled = true }` is set. Ubuntu cloud images do
# not ship the agent, so without this snippet every VM creation AND every
# state refresh burns the full 15-minute agent timeout per VM.
# Installing the agent via cloud-init makes the agent respond within seconds
# of first boot.
#
# "local" storage is per-node, so one snippet per target node is required
# (same pattern as the cloud image downloads in main.tf).

# NOTE: when `user_data_file_id` is set on a VM, this custom cloud-config
# REPLACES the provider-generated one (the `user_account` block in
# `initialization` is NOT merged in). Therefore this snippet must carry the
# COMPLETE cloud-config: the ubuntu user with the lab SSH key AND the
# qemu-guest-agent install.

resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = toset(var.target_nodes)

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value

  source_raw {
    data = <<-EOF
      #cloud-config
      users:
        - name: ubuntu
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          lock_passwd: true
          ssh_authorized_keys:
            - ${var.ssh_public_key}
      ssh_pwauth: false
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOF

    file_name = "k8suth-cloud-config.yaml"
  }

  overwrite = true
}
