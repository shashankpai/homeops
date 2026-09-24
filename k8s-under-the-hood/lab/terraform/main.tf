# ==============================================================================
# Ubuntu Cloud Image Download (one per target node)
# ==============================================================================
# local-lvm is per-node storage (not shared), so we download the official
# Ubuntu 24.04 cloud image to each node that will host a lab VM.
# This avoids any dependency on a template VM and works across nodes.
# Pattern proven in ../../terraform-talos/01-Infrastructure/main.tf

resource "proxmox_download_file" "ubuntu_cloud_image" {
  for_each = toset(var.target_nodes)

  content_type        = "iso"
  datastore_id        = "local"
  node_name           = each.value
  file_name           = var.ubuntu_image_filename
  url                 = var.ubuntu_image_url
  overwrite           = true
  overwrite_unmanaged = true
}

# ==============================================================================
# Master node (on pve4 / 192.168.1.47, 16GB RAM host)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "master" {
  name        = var.vm_names["master"]
  description = "K3s master node - k8s-under-the-hood lab"
  node_name   = var.vm_nodes["master"]
  vm_id       = var.vm_ids["master"]
  tags        = concat(var.tags, ["master"])
  on_boot     = true

  cpu {
    cores = var.master_config.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.master_config.memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image[var.vm_nodes["master"]].id
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.master_config.disk
  }

  network_device {
    bridge = var.network_bridge
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${var.vm_ips["master"]}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      initialization
    ]
  }
}

# ==============================================================================
# Worker 1 (on pve2 / 192.168.1.87, 8GB RAM host)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "worker1" {
  depends_on  = [proxmox_virtual_environment_vm.master]
  name        = var.vm_names["worker1"]
  description = "K3s worker node 1 - k8s-under-the-hood lab"
  node_name   = var.vm_nodes["worker1"]
  vm_id       = var.vm_ids["worker1"]
  tags        = concat(var.tags, ["worker"])
  on_boot     = true

  cpu {
    cores = var.worker_config.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_config.memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image[var.vm_nodes["worker1"]].id
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.worker_config.disk
  }

  network_device {
    bridge = var.network_bridge
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${var.vm_ips["worker1"]}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      initialization
    ]
  }
}

# ==============================================================================
# Worker 2 (on pve3 / 192.168.1.25, 8GB RAM host)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "worker2" {
  depends_on  = [proxmox_virtual_environment_vm.master]
  name        = var.vm_names["worker2"]
  description = "K3s worker node 2 - k8s-under-the-hood lab"
  node_name   = var.vm_nodes["worker2"]
  vm_id       = var.vm_ids["worker2"]
  tags        = concat(var.tags, ["worker"])
  on_boot     = true

  cpu {
    cores = var.worker_config.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_config.memory
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.ubuntu_cloud_image[var.vm_nodes["worker2"]].id
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.worker_config.disk
  }

  network_device {
    bridge = var.network_bridge
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${var.vm_ips["worker2"]}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      initialization
    ]
  }
}

# ==============================================================================
# Wait for VMs to boot before generating inventory
# ==============================================================================

resource "time_sleep" "wait_for_vms" {
  depends_on = [
    proxmox_virtual_environment_vm.master,
    proxmox_virtual_environment_vm.worker1,
    proxmox_virtual_environment_vm.worker2
  ]
  create_duration = "60s"
}

# ==============================================================================
# Generate Ansible inventory
# ==============================================================================

resource "local_file" "ansible_inventory" {
  depends_on = [time_sleep.wait_for_vms, null_resource.minio_bucket_setup]

  content = templatefile("${path.module}/../ansible/inventory.ini.tpl", {
    master_ip  = var.vm_ips["master"]
    worker1_ip = var.vm_ips["worker1"]
    worker2_ip = var.vm_ips["worker2"]
  })

  filename = "${path.module}/../ansible/inventory.ini"
}
