variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (any node serves the whole cluster API)"
  type        = string
  default     = "https://192.168.1.48:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!token-name). One cluster-level token manages all nodes."
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "vm_nodes" {
  description = "Proxmox node placement for each lab VM. pve (.48) is intentionally excluded — no lab VMs on the main node."
  type        = map(string)
  default = {
    master  = "pve4" # 192.168.1.47, 16GB RAM
    worker1 = "pve2" # 192.168.1.87, 8GB RAM
    worker2 = "pve3" # 192.168.1.25, 8GB RAM
  }
}

variable "target_nodes" {
  description = "All Proxmox nodes that receive the Ubuntu cloud image download"
  type        = list(string)
  default     = ["pve2", "pve3", "pve4"]
}

variable "ubuntu_image_url" {
  description = "Ubuntu 24.04 LTS cloud image (qcow2) URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_image_filename" {
  description = "Filename for the downloaded Ubuntu cloud image on each node"
  type        = string
  default     = "ubuntu-24.04-noble-server-cloudimg-amd64.img"
}

variable "vm_ids" {
  description = "VM IDs for the cluster"
  type        = map(number)
  default = {
    master  = 1100
    worker1 = 1101
    worker2 = 1102
  }
}

variable "vm_ips" {
  description = "Static IPs for the VMs"
  type        = map(string)
  default = {
    master  = "192.168.1.81"
    worker1 = "192.168.1.82"
    worker2 = "192.168.1.83"
  }
}

variable "vm_names" {
  description = "VM names"
  type        = map(string)
  default = {
    master  = "k8suth-master"
    worker1 = "k8suth-worker1"
    worker2 = "k8suth-worker2"
  }
}

variable "master_config" {
  description = "Master node configuration (hosted on pve4/.47 with 16GB RAM — extra headroom for K3s server + etcd + observability)"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    cores  = 2
    memory = 6144
    disk   = 30
  }
}

variable "worker_config" {
  description = "Worker node configuration (hosted on pve2/.87 and pve3/.25 with 8GB RAM each — sized to leave Proxmox host overhead)"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    cores  = 2
    memory = 4096
    disk   = 30
  }
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["192.168.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "SSH public key for VMs"
  type        = string
}

variable "tags" {
  description = "Tags for VMs"
  type        = list(string)
  default     = ["k8s-under-the-hood", "terraform"]
}
