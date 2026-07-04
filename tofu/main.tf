# ── SSH-nøgle ────────────────────────────────────────────────────────────────

# Uploads the local SSH public key to Hetzner so it can be injected into new
# servers at creation time. Without this resource we would have no way to log
# in to a freshly created server.
resource "hcloud_ssh_key" "default" {
  name       = "hetzner-key"
  public_key = file(var.ssh_public_key_path)

  lifecycle {
    # The public key was imported from an existing Hetzner resource.
    # Hetzner strips the comment from the stored key, so the local .pub file
    # and the remote value will always differ — ignoring prevents an unwanted
    # replacement. Name is also ignored to avoid drift from manual renames.
    ignore_changes = [public_key, name]
  }
}

# ── Privat netværk ───────────────────────────────────────────────────────────

# Creates a private Layer-3 network inside Hetzner.
# This gives the server a stable private IP that other Hetzner resources
# (e.g. future nodes or managed databases) can use to communicate without
# going over the public internet.
resource "hcloud_network" "platform" {
  name     = "platform-network"
  ip_range = var.network_ip_range
}

# A network must be divided into subnets before servers can be attached.
# This subnet covers the first /24 of the private network and is placed in
# the eu-central zone to match the server location (hel1).
resource "hcloud_network_subnet" "platform" {
  network_id   = hcloud_network.platform.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}

# ── Server ───────────────────────────────────────────────────────────────────

# The main VPS that runs the k3s cluster.
# A single-node cluster is sufficient for the current workload and keeps
# costs low. The server is attached to the private network so pods can
# communicate over private IPs.
#
# k3s itself is NOT installed here. Installation and upgrades are owned by
# Ansible (ansible/infra.yml), which templates /etc/rancher/k3s/config.yaml
# and (re-)runs the k3s install script — that keeps the install idempotent
# and re-appliable, which a one-shot cloud-init user_data script cannot be.
resource "hcloud_server" "platform" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.server_location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Automatic rolling Hetzner backups (whole-disk snapshots, ~7 daily).
  # Covers OS, k3s state and any local-path-provisioner volume data. Costs
  # ~20% on top of the server price — the simplest available protection
  # against losing the single node this cluster runs on.
  backups = true

  # Attach the server to the private subnet with a fixed IP (.1 in the subnet)
  # so the address is predictable and does not change on reboot
  network {
    network_id = hcloud_network.platform.id
    ip         = cidrhost(var.subnet_ip_range, 1)
  }

  # The subnet must exist before the server can be attached to it
  depends_on = [hcloud_network_subnet.platform]

  lifecycle {
    # These fields are set only at creation time by Hetzner and cannot be
    # changed in-place — ignoring them prevents OpenTofu from proposing a
    # destructive replacement after the server was imported into state.
    ignore_changes = [image, ssh_keys]
  }
}

# ── Firewall ─────────────────────────────────────────────────────────────────

# Hetzner-level firewall (stateful, applied before traffic reaches the server).
# Only the ports we actively use are opened; everything else is dropped by default.
resource "hcloud_firewall" "platform" {
  name = "platform-firewall"

  # SSH — needed for Ansible and manual administration
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP — needed for ACME HTTP-01 challenges (cert-manager / Caddy) and
  # plain-HTTP → HTTPS redirects
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS (TCP) — main TLS traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS (UDP) — required for HTTP/3 (QUIC), which runs over UDP 443
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # The k3s API server (6443) is intentionally NOT exposed publicly here.
  # Cluster-admin credentials over the internet is unnecessary attack surface
  # for a project that has exactly one operator. Reach it instead through an
  # SSH tunnel over the already-open port 22:
  #   ssh -L 6443:localhost:6443 -N -f root@<server_ipv4>
  # kubeconfig.yml points at 127.0.0.1:6443, so kubectl/helm/tofu all work
  # against that tunnel without any extra configuration. See README.md.
}

# Attaches the firewall to the server.
# Kept as a separate resource (rather than inline) so the firewall rules can
# be managed and reused independently of the server lifecycle.
resource "hcloud_firewall_attachment" "platform" {
  firewall_id = hcloud_firewall.platform.id
  server_ids  = [hcloud_server.platform.id]
}
