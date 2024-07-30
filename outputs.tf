output "workstations_ips" {
  value = azurerm_windows_virtual_machine.vm[*].public_ip_address
}
