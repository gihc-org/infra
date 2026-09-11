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

# Image til den delte coturn-instans (se docs/adr/0003-delt-turn-platform.md).
# Pinnet med BÅDE tag og digest: et deploy skal give præcis den samme binære
# coturn, uanset hvornår det køres. Digest'en er Docker Hubs manifest-list-
# digest og dækker linux/amd64 (nodens arkitektur).
variable "coturn_image" {
  type        = string
  default     = "coturn/coturn:4.18.0@sha256:bbefd3e1fdfdc0d58770fe01b581fd8b00d9f3a5580d00acb77cf719a6bc78e3"
  description = "coturn-image (tag + digest) til platform-Deployment'et"
}

# Realm for den delte TURN-tjeneste. Klienterne forbinder til dette navn, og
# coturn bruger det i HMAC-credentials — præcis som i appens config.js.
variable "coturn_realm" {
  type        = string
  default     = "turn.gihc.online"
  description = "TURN-realm (det domæne klienterne forbinder til)"
}
