output "server_ipv4" {
  value       = hcloud_server.platform.ipv4_address
  description = "VPS public IP — bruges i ansible/inventory.yml"
}

output "server_id" {
  value = hcloud_server.platform.id
}

output "kubeconfig_command" {
  value       = "ssh root@${hcloud_server.platform.ipv4_address} 'cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/${hcloud_server.platform.ipv4_address}/g' > ~/.kube/config"
  description = "Kør denne kommando for at hente kubeconfig efter serveren er klar"
}
