variable "server_name" {
  type    = string
  default = "ubuntu-4gb-hel1-1"
}

variable "server_type" {
  type    = string
  default = "cpx22"
}

variable "server_location" {
  type    = string
  default = "hel1"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.hetzner.pub"
}

variable "k3s_version" {
  type        = string
  default     = "latest"
  description = "k3s version to install, e.g. 'v1.29.4+k3s1' or 'latest'"
}

variable "network_zone" {
  type        = string
  default     = "eu-central"
  description = "Hetzner network zone for the private network"
}

variable "network_ip_range" {
  type        = string
  default     = "10.0.0.0/8"
  description = "IP range for the private network"
}

variable "subnet_ip_range" {
  type        = string
  default     = "10.0.1.0/24"
  description = "IP range for the subnet"
}
