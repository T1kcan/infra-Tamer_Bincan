output "master_ips" {
  value = [for vm in proxmox_vm_qemu.master : vm.default_ipv4_address]
}
output "worker_ips" {
  value = [for vm in proxmox_vm_qemu.worker : vm.default_ipv4_address]
}
output "master_names" {
  value = [for vm in proxmox_vm_qemu.master : vm.name]
}
output "worker_names" {
  value = [for vm in proxmox_vm_qemu.worker : vm.name]
}
output "master_ids" {
  value = [for vm in proxmox_vm_qemu.master : vm.id]
}
output "worker_ids" {
  value = [for vm in proxmox_vm_qemu.worker : vm.id]
}

