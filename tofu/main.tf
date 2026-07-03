# ── SSH-nøgle ────────────────────────────────────────────────────────────────

resource "hcloud_ssh_key" "default" {
  name       = "hetzner-key"
  public_key = file(var.ssh_public_key_path)

  lifecycle {
    ignore_changes = [public_key, name]
  }
}

# ── Privat netværk ───────────────────────────────────────────────────────────

resource "hcloud_network" "platform" {
  name     = "platform-network"
  ip_range = var.network_ip_range
}

resource "hcloud_network_subnet" "platform" {
  network_id   = hcloud_network.platform.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}

# ── Server ───────────────────────────────────────────────────────────────────

locals {
  k3s_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    # Vent på at apt er klar
    until apt-get update -y; do sleep 5; done

    # Installer k3s
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${var.k3s_version == "latest" ? "" : var.k3s_version}" sh -s - \
      --disable traefik \
      --flannel-iface eth1 \
      --node-ip $(hostname -I | awk '{print $2}') \
      --tls-san $(curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4)

    # Gør kubeconfig tilgængelig for root
    chmod 644 /etc/rancher/k3s/k3s.yaml
  EOT
}

resource "hcloud_server" "platform" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.server_location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.default.id]
  user_data   = local.k3s_install_script

  network {
    network_id = hcloud_network.platform.id
    ip         = cidrhost(var.subnet_ip_range, 1)
  }

  depends_on = [hcloud_network_subnet.platform]

  lifecycle {
    # image, ssh_keys og user_data sættes kun ved oprettelse — ignorér drift efter import
    ignore_changes = [image, ssh_keys, user_data]
  }
}

# ── Firewall ─────────────────────────────────────────────────────────────────

resource "hcloud_firewall" "platform" {
  name = "platform-firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # k3s API — kubectl-adgang fra din maskine
  # Kan indsnævres til din egen IP: ["DIN_IP/32"]
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall_attachment" "platform" {
  firewall_id = hcloud_firewall.platform.id
  server_ids  = [hcloud_server.platform.id]
}
