output "server_ipv4" {
  value       = hcloud_server.platform.ipv4_address
  description = "VPS public IP — bruges i ansible/inventory.yml"
}

output "server_id" {
  value = hcloud_server.platform.id
}
