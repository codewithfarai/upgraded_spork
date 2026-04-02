provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "default" {
  name = "${var.project_name}_ssh_key_${var.environment}"
  # Use dynamically injected var.ssh_key (from CI) if available. Otherwise, fallback to the local ssh_keys map.
  public_key = var.ssh_key != null ? var.ssh_key : lookup(var.ssh_keys, var.environment, var.ssh_public_key)
}

locals {
  common_labels = {
    environment = var.environment
    system      = var.project_name
  }
}


# Private Network
resource "hcloud_network" "main" {
  name     = "${var.project_name}_private_network_${var.environment}"
  ip_range = var.network_ip_range
  labels = merge(local.common_labels, {
    type = var.network_label_type
  })
}

# Transparent NAT Gateway Route
# All internet traffic (0.0.0.0/0) will be routed through the Edge node (10.0.1.20)
resource "hcloud_network_route" "nat_gateway" {
  network_id  = hcloud_network.main.id
  destination = "0.0.0.0/0"
  gateway     = "10.0.1.20"
}

# Network Subnets (Dynamic)
resource "hcloud_network_subnet" "subnets" {
  for_each     = var.subnets
  network_id   = hcloud_network.main.id
  ip_range     = each.value
  network_zone = var.network_zone
  type         = var.subnet_type
}

# Bastion Host Firewall
resource "hcloud_firewall" "bastion_ssh" {
  name = "${var.project_name}_bastion_ssh_firewall_${var.environment}"
  # SSH access (Port 22)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.allowed_ssh_ips
    description = "ssh access from allowed admin IPs"
  }

  # === EGRESS RULES ===
  # Bastion only needs: internal SSH, DNS, APT updates, NTP

  # Private network - SSH to internal nodes
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = [var.network_ip_range]
    description     = "All TCP outbound to private network (SSH to nodes)"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = [var.network_ip_range]
    description     = "All UDP outbound to private network"
  }
  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = [var.network_ip_range]
    description     = "ICMP outbound to private network"
  }

  # DNS
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "DNS resolution (UDP)"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "DNS resolution (TCP)"
  }

  # APT updates
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "HTTP outbound (APT updates)"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "HTTPS outbound (APT updates)"
  }

  # NTP
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "123"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "NTP time synchronization"
  }

  # Node Exporter Scraping (from Managers)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "9100"
    source_ips  = [for i in range(var.manager_count) : "10.0.2.${10 + i}/32"]
    description = "Node Exporter scraping from Managers"
  }

  labels = merge(local.common_labels, {
    purpose = "bastion"
    type    = var.firewall_label_type
  })
}

# Internal Firewall (SSH from Bastion & ICMP)
resource "hcloud_firewall" "internal_ssh" {
  name = "${var.project_name}_internal_ssh_firewall_${var.environment}"
  # Internal SSH (from Bastion)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.bastion_internal_ip]
    description = "ssh access from internal network"
  }

  # Internal ICMP (for ping/reachability)
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.network_ip_range]
    description = "Internal ICMP"
  }

  labels = merge(local.common_labels, {
    purpose = "internal"
    type    = var.firewall_label_type
  })
}

# HTTP/HTTPS Firewall for Edge Nodes
resource "hcloud_firewall" "web_traffic" {
  name = "${var.project_name}_web_traffic_firewall_${var.environment}"

  # HTTP (LB Only)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["10.0.1.5/32"]
    description = "Allow HTTP only from Load Balancer"
  }

  labels = merge(local.common_labels, {
    purpose = "web-traffic"
    type    = var.firewall_label_type
  })
}


# Docker Swarm Firewall
resource "hcloud_firewall" "docker_swarm" {
  name = "${var.project_name}_docker_swarm_firewall_${var.environment}"

  # Swarm management
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "2377"
    source_ips  = [var.network_ip_range]
    description = "Docker Swarm manager API (internal only)"
  }

  # Docker API over TCP (for Traefik remote access)
  # rule {
  #   direction   = "in"
  #   protocol    = "tcp"
  #   port        = "2376"
  #   source_ips  = [var.network_ip_range]
  #   description = "Docker API over TCP (internal only)"
  # }

  # Container network discovery
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "7946"
    source_ips  = [var.network_ip_range]
    description = "Container network discovery TCP"
  }
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "7946"
    source_ips  = [var.network_ip_range]
    description = "Container network discovery UDP"
  }

  # Overlay network
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "4789"
    source_ips  = [var.network_ip_range]
    description = "Overlay network VXLAN"
  }

  # IPSec/ESP for encrypted overlay networks
  rule {
    direction   = "in"
    protocol    = "esp"
    source_ips  = [var.network_ip_range]
    description = "IPSec ESP for encrypted overlay"
  }
  # === EGRESS RULES ===
  # Restrict outbound traffic from all Swarm nodes.
  # Without these, compromised nodes could exfiltrate data or establish reverse shells.

  # Private network - all traffic (inter-node communication)
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = [var.network_ip_range]
    description     = "All TCP outbound to private network"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = [var.network_ip_range]
    description     = "All UDP outbound to private network"
  }
  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = [var.network_ip_range]
    description     = "ICMP outbound to private network"
  }

  # IPSec/ESP for encrypted overlay networks outbound
  rule {
    direction       = "out"
    protocol        = "esp"
    destination_ips = [var.network_ip_range]
    description     = "IPSec ESP outbound for encrypted overlay"
  }

  # DNS resolution
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "DNS resolution (UDP)"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "DNS resolution (TCP)"
  }

  # HTTP - APT package updates
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "HTTP outbound (APT updates)"
  }

  # HTTPS - Docker image pulls + APT HTTPS repos
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "HTTPS outbound (Docker pulls, APT updates)"
  }

  # SMTP SSL (port 465) - Authentik email via Resend
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "465"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "SMTP SSL outbound (Resend email)"
  }

  # SMTP STARTTLS (port 587) - fallback SMTP
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "587"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "SMTP STARTTLS outbound (email fallback)"
  }

  # NTP - time synchronization
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "123"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "NTP time synchronization"
  }

  labels = merge(local.common_labels, {
    purpose = "docker_swarm"
    type    = var.firewall_label_type
  })
}

# Database Firewall (Internal Only)
resource "hcloud_firewall" "database" {
  name = "${var.project_name}_database_firewall_${var.environment}"

  # Postgres
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "5432"
    source_ips  = [var.subnets["application"], var.bastion_internal_ip]
    description = "Postgres internal access from application and bastion"
  }

  # MySQL
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "3306"
    source_ips  = [var.subnets["application"], var.bastion_internal_ip]
    description = "MySQL internal access from application and bastion"
  }

  # Redis
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6379"
    source_ips  = [var.subnets["application"], var.bastion_internal_ip]
    description = "Redis internal access from application and bastion"
  }

  labels = merge(local.common_labels, {
    purpose = "database"
    type    = var.firewall_label_type
  })
}

# Bastion Host
resource "hcloud_server" "bastion" {
  name         = "${replace(var.project_name, "_", "-")}-bastion-${var.environment}"
  image        = var.vps_image
  server_type  = var.bastion_server_type
  location     = var.locations[0]
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.bastion_ssh.id]

  network {
    network_id = hcloud_network.main.id
    # Use only the IP address part (e.g., "10.0.2.5") from "10.0.2.5/32"
    ip = split("/", var.bastion_internal_ip)[0]
  }

  user_data = templatefile("${path.module}/scripts/node_init.sh", {
    node_type        = "bastion"
    node_index       = 0
    manager_ip       = "" # Bastion doesn't join the swarm
    worker_count     = var.worker_count[var.environment]
    network_gateway  = cidrhost(var.network_ip_range, 1)
    enable_hardening = var.enable_security_hardening
    fail2ban_config  = jsonencode(var.fail2ban_config)
  })

  labels = merge(local.common_labels, {
    role = "bastion"
  })

  depends_on = [
    hcloud_network.main,
    hcloud_network_subnet.subnets,
    hcloud_firewall.bastion_ssh
  ]
}

# Docker Swarm Manager Nodes
resource "hcloud_server" "manager" {
  count       = var.manager_count
  name        = "${replace(var.project_name, "_", "-")}-manager-${var.environment}-${count.index + 1}"
  image       = var.vps_image
  server_type = var.manager_server_type[var.environment]
  location    = element(var.locations, count.index)
  ssh_keys    = [hcloud_ssh_key.default.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  # Manager is INTERNAL only - no web_traffic firewall!
  firewall_ids = [
    hcloud_firewall.internal_ssh.id,
    hcloud_firewall.docker_swarm.id
  ]
  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.2.${10 + count.index}"
  }

  user_data = templatefile("${path.module}/scripts/node_init.sh", {
    node_type        = "manager"
    node_index       = count.index + 1
    manager_ip       = "10.0.2.10" # Seed manager IP (static mapping)
    worker_count     = var.worker_count[var.environment]
    network_gateway  = cidrhost(var.network_ip_range, 1)
    enable_hardening = var.enable_security_hardening
    fail2ban_config  = jsonencode(var.fail2ban_config)
  })

  labels = merge(local.common_labels, {
    role              = "manager"
    security_hardened = var.enable_security_hardening
    public_access     = "false"
    manager_id        = count.index + 1
  })

  depends_on = [
    hcloud_network.main,
    hcloud_network_subnet.subnets,
    hcloud_firewall.internal_ssh,
    hcloud_firewall.docker_swarm
  ]
}


# Edge/Load Balancer Nodes (Traefik - High Availability)
resource "hcloud_server" "edge" {
  count       = var.edge_count[var.environment]
  name        = "${replace(var.project_name, "_", "-")}-edge-${var.environment}-${count.index + 1}"
  image       = var.vps_image
  server_type = var.edge_server_type[var.environment]
  location    = element(var.locations, count.index)
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Edge accepts public web traffic, internal SSH, and Swarm communication
  firewall_ids = [
    hcloud_firewall.internal_ssh.id,
    hcloud_firewall.web_traffic.id,
    hcloud_firewall.docker_swarm.id
  ]

  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.1.${20 + count.index}"
  }

  user_data = templatefile("${path.module}/scripts/node_init.sh", {
    node_type  = "edge"
    node_index = count.index + 1
    # Point to the primary manager in the management subnet
    manager_ip       = "10.0.2.10"
    worker_count     = var.worker_count[var.environment]
    network_gateway  = cidrhost(var.network_ip_range, 1)
    enable_hardening = var.enable_security_hardening
    fail2ban_config  = jsonencode(var.fail2ban_config)
  })

  labels = merge(local.common_labels, {
    role              = "edge"
    security_hardened = var.enable_security_hardening
    public_access     = "true"
    edge_id           = count.index + 1
  })

  depends_on = [
    hcloud_network.main,
    hcloud_network_subnet.subnets,
    hcloud_firewall.internal_ssh,
    hcloud_firewall.web_traffic,
    hcloud_firewall.docker_swarm,
    hcloud_server.manager
  ]
}

# Managed Load Balancer (TCP Pass-Through)
resource "hcloud_load_balancer" "main" {
  name               = "${var.project_name}_lb_${var.environment}"
  load_balancer_type = var.lb_type
  location           = var.locations[0]
  labels             = local.common_labels
}

resource "hcloud_load_balancer_network" "main" {
  load_balancer_id = hcloud_load_balancer.main.id
  network_id       = hcloud_network.main.id
  ip               = "10.0.1.5"
}

resource "hcloud_load_balancer_target" "edge" {
  count            = var.edge_count[var.environment]
  type             = "server"
  load_balancer_id = hcloud_load_balancer.main.id
  server_id        = hcloud_server.edge[count.index].id
  use_private_ip   = true
  depends_on       = [hcloud_load_balancer_network.main]
}

resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.main.id
  protocol         = "https"
  listen_port      = 443
  destination_port = 80 # Forward to Traefik HTTP
  http {
    certificates  = [hcloud_managed_certificate.wildcard.id]
    redirect_http = true
  }
  health_check {
    protocol = "http"
    port     = 80
    interval = 10
    timeout  = 5
    retries  = 3
    http {
      path = "/ping" # Traefik ping endpoint
    }
  }
}

# Docker Swarm Worker Nodes
resource "hcloud_server" "worker" {
  count       = var.worker_count[var.environment]
  name        = "${replace(var.project_name, "_", "-")}-worker-${var.environment}-${count.index + 1}"
  image       = var.vps_image
  server_type = var.worker_server_type[var.environment]
  location    = element(var.locations, count.index)
  ssh_keys    = [hcloud_ssh_key.default.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  # Workers are INTERNAL only - no web_traffic firewall!
  firewall_ids = [
    hcloud_firewall.internal_ssh.id,
    hcloud_firewall.docker_swarm.id
  ]
  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.3.${30 + count.index}"
  }

  user_data = templatefile("${path.module}/scripts/node_init.sh", {
    node_type        = "worker"
    node_index       = count.index + 1
    manager_ip       = "10.0.2.10" # Primary manager IP in management subnet
    worker_count     = var.worker_count[var.environment]
    network_gateway  = cidrhost(var.network_ip_range, 1)
    enable_hardening = var.enable_security_hardening
    fail2ban_config  = jsonencode(var.fail2ban_config)
  })

  labels = merge(local.common_labels, {
    role              = "worker"
    security_hardened = var.enable_security_hardening
    public_access     = "false"
    worker_id         = count.index + 1
  })

  depends_on = [
    hcloud_network.main,
    hcloud_network_subnet.subnets,
    hcloud_firewall.internal_ssh,
    hcloud_firewall.docker_swarm,
    hcloud_server.manager,
    hcloud_server.edge
  ]
}

# Database Nodes
resource "hcloud_server" "database" {
  count       = var.db_count[var.environment]
  name        = "${replace(var.project_name, "_", "-")}-db-${var.environment}-${count.index + 1}"
  image       = var.vps_image
  server_type = var.db_server_type[var.environment]
  location    = element(var.locations, count.index)
  ssh_keys    = [hcloud_ssh_key.default.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  firewall_ids = [
    hcloud_firewall.internal_ssh.id,
    hcloud_firewall.database.id,
    hcloud_firewall.docker_swarm.id
  ]

  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.4.${10 + count.index}" # Isolated Database Subnet
  }

  user_data = templatefile("${path.module}/scripts/node_init.sh", {
    node_type        = "database"
    node_index       = count.index + 1
    manager_ip       = "10.0.2.10" # Primary manager IP in management subnet
    worker_count     = var.worker_count[var.environment]
    network_gateway  = cidrhost(var.network_ip_range, 1)
    enable_hardening = var.enable_security_hardening
    fail2ban_config  = jsonencode(var.fail2ban_config)
  })

  labels = merge(local.common_labels, {
    role              = "database"
    security_hardened = var.enable_security_hardening
    public_access     = "false"
    db_id             = count.index + 1
  })

  depends_on = [
    hcloud_network.main,
    hcloud_network_subnet.subnets,
    hcloud_firewall.internal_ssh,
    hcloud_firewall.database,
    hcloud_server.manager,
    hcloud_server.edge
  ]
}

# ------------------------------------------------------------------------------
# AUTOMATIC DNS ROUTING (HETZNER DNS)
# ------------------------------------------------------------------------------
data "hcloud_zone" "main" {
  name = var.domain_name
}

resource "hcloud_zone_rrset" "environment_routing" {
  zone = data.hcloud_zone.main.id
  name = var.environment == "prod" ? "@" : var.environment
  type = "A"
  records = [{
    value = hcloud_load_balancer.main.ipv4
  }]
  ttl = 60

  depends_on = [
    hcloud_load_balancer.main
  ]
}

resource "hcloud_zone_rrset" "environment_wildcard" {
  zone = data.hcloud_zone.main.id
  name = var.environment == "prod" ? "*" : "*.${var.environment}"
  type = "A"
  records = [{
    value = hcloud_load_balancer.main.ipv4
  }]
  ttl = 60

  depends_on = [
    hcloud_load_balancer.main
  ]
}
