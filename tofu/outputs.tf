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

# A ready-to-run SSH tunnel command. The k3s API (6443) is not exposed
# publicly (see the firewall in main.tf), so kubectl/helm/tofu all reach it
# through this tunnel — kubeconfig.yml (fetched by ansible/infra.yml) points
# at 127.0.0.1:6443, matching the local end of this tunnel.
output "kubeconfig_tunnel_command" {
  value       = "ssh -L 6443:localhost:6443 -N -f root@${hcloud_server.platform.ipv4_address}"
  description = "Kør denne kommando for at åbne SSH-tunnel til k3s API'en"
}
