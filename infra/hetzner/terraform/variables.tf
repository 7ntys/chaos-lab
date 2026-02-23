variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name of the Hetzner server"
  type        = string
  default     = "chaos-cx23"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cx23"
}

variable "server_image" {
  description = "Image for the server"
  type        = string
  default     = "ubuntu-24.04"
}

variable "server_location" {
  description = "Hetzner location (Germany examples: nbg1, fsn1)"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_key_name" {
  description = "Name of the SSH key in Hetzner"
  type        = string
  default     = "local-id-rsa"
}

variable "labels" {
  description = "Labels to attach to the server"
  type        = map(string)
  default = {
    project = "chaos"
  }
}

variable "ssh_source_cidr" {
  description = "Source CIDR allowed to access SSH (tcp/22)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "http_source_cidr" {
  description = "Source CIDR allowed to access HTTP (tcp/80)"
  type        = string
  default     = "0.0.0.0/0"
}
