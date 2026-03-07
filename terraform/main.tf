provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "default" {
  name       = "fluffy_system_ssh_key_${var.environment}"
  public_key = lookup(var.ssh_keys, var.environment, var.ssh_public_key)
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

  # HTTP
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTP traffic (redirects to HTTPS)"
  }

  # HTTPS
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTPS traffic for Traefik"
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
  location     = var.location
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
  location    = var.location
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
  location    = var.location
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

# Docker Swarm Worker Nodes
resource "hcloud_server" "worker" {
  count       = var.worker_count[var.environment]
  name        = "${replace(var.project_name, "_", "-")}-worker-${var.environment}-${count.index + 1}"
  image       = var.vps_image
  server_type = var.worker_server_type[var.environment]
  location    = var.location
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
  location    = var.location
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
