variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "The root domain name (e.g. ridebase.tech)"
  type        = string
}

variable "project_name" {
  description = "Name of the Project"
  type        = string
}

variable "network_ip_range" {
  description = "The IP range of the network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "network_zone" {
  description = "The network zone for subnets"
  type        = string
  default     = "eu-central"
}

variable "subnet_type" {
  description = "The type of subnets"
  type        = string
  default     = "cloud"
}

variable "subnets" {
  description = "Map of subnet names to their IP ranges"
  type        = map(string)
  default = {
    edge        = "10.0.1.0/24"
    management  = "10.0.2.0/24"
    application = "10.0.3.0/24"
    database    = "10.0.4.0/24"
  }
}

variable "bastion_internal_ip" {
  description = "The internal IP of the bastion host for SSH access"
  type        = string
  default     = "10.0.2.5/32"
}

variable "firewall_label_type" {
  description = "The type label for firewall resources"
  type        = string
  default     = "firewall"
}

variable "network_label_type" {
  description = "The type label for network resources"
  type        = string
  default     = "private"
}

# Environment
variable "environment" {
  description = "Environment name (prod, stage, dev)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["prod", "stage", "dev"], var.environment)
    error_message = "Environment must be prod, stage, or dev"
  }
}

variable "allowed_ssh_ips" {
  type        = list(string)
  description = "List of IPs allowed to SSH into the bastion host"
}

variable "vps_image" {
  description = "Image to use for VPS"
  type        = string
  default     = "ubuntu-24.04"
}

variable "bastion_server_type" {
  description = "Server type for bastion host"
  type        = string
  default     = "cx33"
}


variable "fail2ban_config" {
  description = "Fail2ban configuration for SSH protection"
  type = object({
    bantime      = number
    findtime     = number
    maxretry     = number
    ssh_maxretry = number
  })
  default = {
    bantime      = 3600 # 1 hour ban
    findtime     = 600  # 10 minutes window
    maxretry     = 5    # Max retry attempts
    ssh_maxretry = 3    # Max SSH retry attempts
  }
}

variable "enable_security_hardening" {
  description = "Enable security hardening (SSH hardening, fail2ban, kernel parameters)"
  type        = bool
  default     = true
}

variable "worker_count" {
  description = "Map of environment to number of Docker Swarm worker nodes"
  type        = map(number)
  default = {
    prod  = 2
    stage = 2
    dev   = 2
  }

  validation {
    condition     = alltrue([for k, v in var.worker_count : v >= 1 && v <= 20])
    error_message = "Worker count must be between 1 and 20 for all environments"
  }
}

variable "locations" {
  description = "List of Hetzner datacenter locations for High Availability distribution"
  type        = list(string)
  default     = ["nbg1", "fsn1"] # Nuremberg and Falkenstein
}

variable "manager_count" {
  description = "Number of Docker Swarm manager nodes (1, 3, or 5 recommended for HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.manager_count >= 1 && var.manager_count <= 7 && var.manager_count % 2 == 1
    error_message = "Manager count must be an odd number between 1 and 7 (1, 3, 5, or 7) for proper quorum"
  }
}

variable "manager_server_type" {
  description = "Map of environment to Hetzner server type for manager nodes"
  type        = map(string)
  default = {
    prod  = "cx33"
    stage = "cx33"
    dev   = "cx33"
  }
}
variable "edge_server_type" {
  description = "Map of environment to Hetzner server type for edge nodes (Traefik load balancer)"
  type        = map(string)
  default = {
    prod  = "cx33"
    stage = "cx33"
    dev   = "cx33"
  }
}

variable "lb_type" {
  description = "Type of the Hetzner Load Balancer"
  type        = string
  default     = "lb11"
}

variable "edge_count" {
  description = "Map of environment to number of edge/load balancer nodes"
  type        = map(number)
  default = {
    prod  = 2
    stage = 2
    dev   = 2
  }

  validation {
    condition     = alltrue([for k, v in var.edge_count : v >= 1 && v <= 5])
    error_message = "Edge count must be between 1 and 5 for all environments"
  }
}

variable "worker_server_type" {
  description = "Map of environment to Hetzner server type for worker nodes"
  type        = map(string)
  default = {
    prod  = "cx33"
    stage = "cx33"
    dev   = "cx33"
  }
}

variable "db_server_type" {
  description = "Map of environment to Hetzner server type for database nodes"
  type        = map(string)
  default = {
    prod  = "cx33"
    stage = "cx33"
    dev   = "cx33"
  }
}

variable "db_count" {
  description = "Map of environment to number of database nodes"
  type        = map(number)
  default = {
    prod  = 2
    stage = 2
    dev   = 2
  }

  validation {
    condition     = alltrue([for k, v in var.db_count : v >= 1 && v <= 3])
    error_message = "DB count must be between 1 and 3 for all environments"
  }
}



variable "ssh_public_key" {
  description = "public ssh key for server access. Optional if ssh_key is set."
  sensitive   = true
  type        = string
  default     = null
}

variable "ssh_key" {
  description = "Environment-specific SSH public key provided via CI."
  type        = string
  default     = null
}

variable "ssh_keys" {
  description = "Map of environment to SSH public key. (Used locally from tfvars)."
  type        = map(string)
  default     = {}
}
