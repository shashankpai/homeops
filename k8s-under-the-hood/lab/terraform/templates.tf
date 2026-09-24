# ==============================================================================
# Ubuntu 24.04 Template (one per target node)
# ==============================================================================
# local-lvm is per-node storage (not shared), so each node that hosts lab VMs
# gets its own template. Templates are created ONCE (bootstrap); lab VMs are
# then FULL CLONES of them via the Proxmox clone API.
#
# WHY THIS DESIGN:
#   - Cloning is a first-class Proxmox API operation (no SSH required)
#   - Disk-from-image import (the OLD approach) has no API endpoint and
#     requires the provider to SSH into the node to run import commands
#   - With templates, SSH is needed ONLY for this one-time bootstrap
#
# ONE-TIME BOOTSTRAP (requires SSH to Proxmox nodes):
#   make templates
#
# After bootstrap, ALL subsequent operations (clone, destroy, rebuild) are
# API-only and can run from ANY controller with just the Proxmox API token.

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  for_each = toset(var.target_nodes)

  # Static map: VM IDs are cluster-wide unique in Proxmox. 9000/9002 are
  # already taken by other VMs (ubuntu-22.04 template, opnsense on node pve).
  vm_id       = { pve2 = 9100, pve3 = 9101, pve4 = 9102 }[each.value]
  name        = "ubuntu-2404-${each.value}"
  description = "Ubuntu 24.04 cloud image template - k8s-under-the-hood lab (source for API-only clones)"
  node_name   = each.value
  template    = true
  tags        = concat(var.tags, ["template"])

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Disk size matches the largest lab VM disk (30GB) so clones inherit
  # sufficient space. Clones can still resize via their own disk block.
  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image[each.value].id
    file_format  = "raw"
    interface    = "scsi0"
    size         = 30
  }

  network_device {
    bridge = var.network_bridge
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  # Templates are never booted, so no initialization (cloud-init) is needed
  # here. Each cloned VM applies its own cloud-init config via the API.
}
