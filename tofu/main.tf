# ── SSH-nøgle ────────────────────────────────────────────────────────────────

resource "hcloud_ssh_key" "default" {
  name       = "hetzner-key"
  public_key = file(var.ssh_public_key_path)

  lifecycle {
    ignore_changes = [public_key, name]
  }
}

# ── Server ───────────────────────────────────────────────────────────────────

resource "hcloud_server" "platform" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.server_location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.default.id]

  lifecycle {
    # image og ssh_keys sættes kun ved oprettelse — ignorér drift efter import
    ignore_changes = [image, ssh_keys]
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
