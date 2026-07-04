# Name assigned to the server in the Hetzner Cloud console
variable "server_name" {
  type    = string
  default = "ubuntu-4gb-hel1-1"
}

# Hetzner server type — cpx22 is 3 vCPU / 4 GB RAM (AMD, shared)
variable "server_type" {
  type    = string
  default = "cpx22"
}

# Hetzner datacenter location — hel1 is Helsinki
variable "server_location" {
  type    = string
  default = "hel1"
}

# Path to the SSH public key that will be added to the server at creation time,
# allowing passwordless root login
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.hetzner.pub"
}

# k3s version to install on the server.
# Use "latest" to always get the newest stable release, or pin to a specific
# version such as "v1.29.4+k3s1" for reproducible builds.
variable "k3s_version" {
  type        = string
  default     = "latest"
  description = "k3s version to install, e.g. 'v1.29.4+k3s1' or 'latest'"
}

# Hetzner network zone for the private network.
# eu-central covers hel1, fsn1 and nbg1.
variable "network_zone" {
  type        = string
  default     = "eu-central"
  description = "Hetzner network zone for the private network"
}

# The overall IP range for the private network.
# A /8 gives plenty of room for future subnets.
variable "network_ip_range" {
  type        = string
  default     = "10.0.0.0/8"
  description = "IP range for the private network"
}

# The IP range for the single subnet we attach the server to.
# The server gets the first host address in this range (10.0.1.1).
variable "subnet_ip_range" {
  type        = string
  default     = "10.0.1.0/24"
  description = "IP range for the subnet"
}
