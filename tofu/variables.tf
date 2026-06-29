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
