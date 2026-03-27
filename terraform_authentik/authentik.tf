provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

locals {
  env_subdomain = var.environment == "prod" ? "" : "${var.environment}."
}

data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_flow" "default_authentication_flow" {
  slug = "default-authentication-flow"
}

resource "authentik_provider_proxy" "traefik" {
  name               = "traefik-proxy"
  external_host      = "https://traefik.${local.env_subdomain}${var.domain_name}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_provider_proxy" "grafana" {
  name               = "grafana-proxy"
  external_host      = "https://grafana.${local.env_subdomain}${var.domain_name}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_proxy.grafana.id
}

resource "authentik_provider_proxy" "prometheus" {
  name               = "prometheus-proxy"
  external_host      = "https://prometheus.${local.env_subdomain}${var.domain_name}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "prometheus" {
  name              = "Prometheus"
  slug              = "prometheus"
  protocol_provider = authentik_provider_proxy.prometheus.id
}

resource "authentik_provider_proxy" "rabbitmq" {
  name               = "rabbitmq-proxy"
  external_host      = "https://rabbitmq.${local.env_subdomain}${var.domain_name}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "rabbitmq" {
  name              = "RabbitMQ Management"
  slug              = "rabbitmq"
  protocol_provider = authentik_provider_proxy.rabbitmq.id
}

# --- RIDEBASE APP ---
resource "authentik_provider_proxy" "ridebase" {
  name               = "ridebase-proxy"
  external_host      = "https://ridebase.${local.env_subdomain}${var.domain_name}"
  authorization_flow = data.authentik_flow.default_authentication_flow.id # Use standard auth flow
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "ridebase" {
  name              = "Ridebase"
  slug              = "ridebase"
  protocol_provider = authentik_provider_proxy.ridebase.id
}

resource "null_resource" "bind_embedded_outpost" {
  depends_on = [
    authentik_provider_proxy.traefik,
    authentik_provider_proxy.grafana,
    authentik_provider_proxy.prometheus,
    authentik_provider_proxy.rabbitmq
  ]

  triggers = {
    provider_ids = join(",", [
      authentik_provider_proxy.traefik.id,
      authentik_provider_proxy.grafana.id,
      authentik_provider_proxy.prometheus.id,
      authentik_provider_proxy.rabbitmq.id,
      authentik_provider_proxy.ridebase.id
    ])
  }

  provisioner "local-exec" {
    command = <<EOT
      OUTPOST_ID=$(curl -sk \
        -H "Authorization: Bearer ${var.authentik_token}" \
        "${var.authentik_url}/api/v3/outposts/instances/?name=authentik+Embedded+Outpost" \
        | jq -r '.results[0].pk')
      echo "Outpost ID: $OUTPOST_ID"
      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.authentik_token}" \
        -H "Content-Type: application/json" \
        -d "{\"providers\": [${self.triggers.provider_ids}], \"config\": {\"authentik_host\": \"${var.authentik_url}\"}}" \
        "${var.authentik_url}/api/v3/outposts/instances/$OUTPOST_ID/" \
        | jq .
    EOT
  }
}

resource "authentik_application" "traefik" {
  name              = "Traefik Dashboard"
  slug              = "traefik"
  protocol_provider = authentik_provider_proxy.traefik.id
}
