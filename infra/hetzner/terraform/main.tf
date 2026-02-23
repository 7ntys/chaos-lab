provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "this" {
  name       = var.ssh_key_name
  public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "hcloud_firewall" "this" {
  name = "${var.server_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.ssh_source_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = [var.http_source_cidr]
  }
}

resource "hcloud_server" "this" {
  name        = var.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.server_location
  ssh_keys    = [hcloud_ssh_key.this.id]
  firewall_ids = [
    hcloud_firewall.this.id,
  ]
  labels = var.labels
}
