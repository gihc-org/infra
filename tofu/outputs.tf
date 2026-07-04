# The server's public IPv4 address.
# Primary use: paste this into ansible/inventory.yml so Ansible knows which
# host to connect to. Also used to construct the kubeconfig_command below.
output "server_ipv4" {
  value       = hcloud_server.platform.ipv4_address
  description = "VPS public IP — bruges i ansible/inventory.yml"
}

# The numeric Hetzner server ID.
# Useful when you need to reference the server in the Hetzner Cloud console
# or when importing the resource into a fresh OpenTofu state.
output "server_id" {
  value = hcloud_server.platform.id
}

# A ready-to-run shell command that fetches the k3s kubeconfig from the server
# and rewrites the loopback address (127.0.0.1) to the public IP so that
# kubectl can reach the API server from your local machine.
# Run this once after the server has finished its cloud-init boot sequence.
output "kubeconfig_command" {
  value       = "ssh root@${hcloud_server.platform.ipv4_address} 'cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/${hcloud_server.platform.ipv4_address}/g' > ~/.kube/config"
  description = "Kør denne kommando for at hente kubeconfig efter serveren er klar"
}
