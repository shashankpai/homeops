locals {
  # Keep these IPs and names in sync with ansible/inventory.ini and ansible/group_vars/all/main.yml
  vms = {
    forgejo   = { vm_id = 201, ip = "192.168.1.50", cores = 2, memory = 4096, disk_gb = 40 }
    authentik = { vm_id = 202, ip = "192.168.1.51", cores = 2, memory = 4096, disk_gb = 30 }
    runner-01 = { vm_id = 203, ip = "192.168.1.52", cores = 4, memory = 8192, disk_gb = 60 }
  }
}

resource "proxmox_download_file" "debian_cloud" {
  content_type        = "import"
  datastore_id        = var.image_datastore
  node_name           = var.node_name
  url                 = var.debian_image_url
  file_name           = "debian-12-genericcloud-amd64.qcow2"
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each  = local.vms
  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = ["forgejo-stack"]
  on_boot   = true
  started   = true

  # Guest agent is installed by the Ansible common role. Flip to true and re-apply afterwards.
  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.debian_cloud.id
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.netmask_bits}"
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.admin_user
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }
}
