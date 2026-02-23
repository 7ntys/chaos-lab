output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.this.id
}

output "server_name" {
  description = "Hetzner server name"
  value       = hcloud_server.this.name
}

output "server_ipv4" {
  description = "Public IPv4"
  value       = hcloud_server.this.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6"
  value       = hcloud_server.this.ipv6_address
}

output "ssh_command" {
  description = "Ready-to-use SSH command"
  value       = "ssh root@${hcloud_server.this.ipv4_address}"
}

output "app_url" {
  description = "Public URL for the load-balanced app"
  value       = "http://${hcloud_server.this.ipv4_address}"
}
