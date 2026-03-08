output "load_balancer_public_ipv4" {
  value       = hcloud_load_balancer.main.ipv4
  description = "The public IPv4 address of the Hetzner Load Balancer"
}

output "load_balancer_public_ipv6" {
  value       = hcloud_load_balancer.main.ipv6
  description = "The public IPv6 address of the Hetzner Load Balancer"
}

output "ssh_key_fingerprint" {
  value       = hcloud_ssh_key.default.fingerprint
  description = "The fingerprint of the SSH key being used for the current environment"
  sensitive   = true
}

output "ssh_public_key" {
  value       = hcloud_ssh_key.default.public_key
  description = "The public key string for the current environment"
  sensitive   = true
}

output "bastion_public_ip" {
  value       = hcloud_server.bastion.ipv4_address
  description = "The public IPv4 address of the bastion host"
}

output "edge_public_ips" {
  value       = hcloud_server.edge[*].ipv4_address
  description = "The public IPv4 addresses of the edge nodes (NAT Gateways)"
}

output "internal_ips" {
  value = {
    managers = hcloud_server.manager[*].network[*].ip
    workers  = hcloud_server.worker[*].network[*].ip
    edge     = hcloud_server.edge[*].network[*].ip
    database = hcloud_server.database[*].network[*].ip
  }
  description = "Map of internal IP addresses for all nodes"
}

output "hcloud_nameservers" {
  value       = data.hcloud_zone.main.authoritative_nameservers.assigned
  description = "The Nameservers assigned by Hetzner. Paste these into your Domain Registrar (e.g. GoDaddy)!"
}
