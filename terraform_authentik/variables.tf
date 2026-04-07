variable "environment" {
  description = "Environment name (prod, stage, dev)"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "The root domain name (e.g. ridebase.tech)"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API Token, populated by Ansible."
  type        = string
  sensitive   = true
}

variable "authentik_url" {
  description = "Authentik URL, populated by Ansible."
  type        = string
}
