output "load_balancer_public_ipv4" {
  value       = hcloud_load_balancer.main.ipv4
  description = "The public IPv4 address of the Hetzner Load Balancer"
}

output "load_balancer_public_ipv6" {
  value       = hcloud_load_balancer.main.ipv6
  description = "The public IPv6 address of the Hetzner Load Balancer"
}
