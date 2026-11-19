output "vm_addresses" {
  description = "Static LAN addresses of the stack VMs (must match ansible/inventory.ini)"
  value       = { for name, vm in local.vms : name => vm.ip }
}

output "vm_ids" {
  description = "Proxmox VM IDs"
  value       = { for name, res in proxmox_virtual_environment_vm.vm : name => res.vm_id }
}
