variable "pm_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  default     = "https://192.168.1.23:8006/"
}

variable "pm_api_token" {
  description = "Proxmox API token (terraform@pve!tf=...)"
  type        = string
  sensitive   = true
}

variable "pm_insecure" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "image_datastore" {
  description = "Datastore with 'import' content enabled (cloud image download target)"
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Linux bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "LAN gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "netmask_bits" {
  description = "Prefix length for the LAN"
  type        = number
  default     = 24
}

variable "dns_servers" {
  description = "DNS servers for the VMs"
  type        = list(string)
  default     = ["192.168.1.1", "1.1.1.1"]
}

variable "admin_user" {
  description = "Sudo user created by cloud-init on each VM (Ansible connects as this user)"
  type        = string
  default     = "devops"
}

variable "ssh_public_key_path" {
  description = "Public key injected into the admin user"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "debian_image_url" {
  description = "Debian 12 (bookworm) generic cloud image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}
