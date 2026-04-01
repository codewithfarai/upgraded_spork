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

# ==============================================================================
# Google OAuth Source (Social Login)
# ==============================================================================
data "authentik_flow" "default_source_enrollment" {
  slug = "default-source-enrollment"
}

resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  authentication_flow = data.authentik_flow.default_authentication_flow.id
  enrollment_flow     = data.authentik_flow.default_source_enrollment.id
  provider_type       = "google"
  consumer_key        = var.google_client_id
  consumer_secret     = var.google_client_secret
  user_matching_mode  = "identifier"
}

# Bind Google to the default login identification stage
data "authentik_stage" "default_authentication_identification" {
  name = "default-authentication-identification"
}

resource "null_resource" "bind_google_to_login" {
  depends_on = [authentik_source_oauth.google]

  triggers = {
    google_source_uuid = authentik_source_oauth.google.uuid
    stage_id           = data.authentik_stage.default_authentication_identification.id
  }

  provisioner "local-exec" {
    command = <<EOT
      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.authentik_token}" \
        -H "Content-Type: application/json" \
        -d "{\"sources\": [\"${authentik_source_oauth.google.uuid}\"]}" \
        "${var.authentik_url}/api/v3/stages/identification/${data.authentik_stage.default_authentication_identification.id}/" \
        | jq .
    EOT
  }
}

# ==============================================================================
# RideBase Groups
# ==============================================================================
resource "authentik_group" "ridebase_drivers" {
  name         = "ridebase_drivers"
  is_superuser = false
}

resource "authentik_group" "ridebase_riders" {
  name         = "ridebase_riders"
  is_superuser = false
}

# ==============================================================================
# RideBase OAuth2/OIDC Provider
# ==============================================================================
data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

resource "authentik_provider_oauth2" "ridebase" {
  name               = "RideBase Provider"
  client_id          = "ridebase"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  client_type        = "public"
  allowed_redirect_uris = [
    { matching_mode = "strict", url = "ridebase://callback" }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
  ]
}

resource "authentik_application" "ridebase" {
  name              = "RideBase"
  slug              = "ridebase"
  protocol_provider = authentik_provider_oauth2.ridebase.id
}

# ==============================================================================
# Embedded Outpost (proxy providers only — RideBase is now OAuth2, not proxied)
# ==============================================================================
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
      authentik_provider_proxy.rabbitmq.id
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
