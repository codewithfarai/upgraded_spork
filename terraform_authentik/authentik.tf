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



# ==============================================================================
# Admin Access Group
# ==============================================================================
data "authentik_group" "admins" {
  name = "authentik Admins"
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

resource "authentik_policy_binding" "grafana_access" {
  target = authentik_application.grafana.uuid
  group  = data.authentik_group.admins.id
  order  = 0
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

resource "authentik_policy_binding" "prometheus_access" {
  target = authentik_application.prometheus.uuid
  group  = data.authentik_group.admins.id
  order  = 0
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

resource "authentik_policy_binding" "rabbitmq_access" {
  target = authentik_application.rabbitmq.uuid
  group  = data.authentik_group.admins.id
  order  = 0
}

# ==============================================================================
# Google OAuth Source (Social Login)
# ==============================================================================


data "authentik_flow" "default_source_authentication" {
  slug = "default-source-authentication"
}

resource "authentik_flow" "google_enrollment" {
  name        = "ridebase-google-enrollment"
  slug        = "ridebase-google-enrollment"
  title       = "Sign Up with Google"
  designation = "enrollment"
}

# 1. Custom Google Enrollment Prompt (Asks for Username)
resource "authentik_stage_prompt" "google_enrollment_prompt" {
  name = "ridebase-google-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.username.id
  ]
}

# 2. Bind the custom prompt to the Google flow
resource "authentik_flow_stage_binding" "google_enroll_prompt" {
  target = authentik_flow.google_enrollment.uuid
  stage  = authentik_stage_prompt.google_enrollment_prompt.id
  order  = 5
}

resource "authentik_stage_user_write" "google_user_write" {
  name                     = "ridebase-google-user-write"
  create_users_as_inactive = false
  create_users_group       = authentik_group.ridebase_riders.id
}

resource "authentik_flow_stage_binding" "google_enroll_write" {
  target = authentik_flow.google_enrollment.uuid
  stage  = authentik_stage_user_write.google_user_write.id
  order  = 10
}

resource "authentik_flow_stage_binding" "google_enroll_login" {
  target = authentik_flow.google_enrollment.uuid
  stage  = authentik_stage_user_login.default_login.id
  order  = 20
}

resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  authentication_flow = data.authentik_flow.default_source_authentication.id
  enrollment_flow     = authentik_flow.google_enrollment.uuid
  provider_type       = "google"
  consumer_key        = var.google_client_id
  consumer_secret     = var.google_client_secret
  user_matching_mode  = "email_link"

  lifecycle {
    ignore_changes = [
      access_token_url,
      authorization_url,
      oidc_jwks_url,
      profile_url,
    ]
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
# RideBase Enrollment (Sign-up) Flow
# Flow: prompt → user_write (inactive) → email OTP → user_login
# ==============================================================================
resource "authentik_flow" "ridebase_enrollment" {
  name        = "ridebase-enrollment"
  slug        = "ridebase-enrollment"
  title       = "Create your RideBase account"
  designation = "enrollment"
}

# Prompt fields
resource "authentik_stage_prompt_field" "username" {
  name      = "username"
  field_key = "username"
  label     = "Username"
  type      = "username"
  required  = true
  order     = 0
}

resource "authentik_stage_prompt_field" "email" {
  name      = "email"
  field_key = "email"
  label     = "Email"
  type      = "email"
  required  = true
  order     = 1
}

resource "authentik_stage_prompt_field" "password" {
  name      = "password"
  field_key = "password"
  label     = "Password"
  type      = "password"
  required  = true
  order     = 2
}

resource "authentik_stage_prompt_field" "password_repeat" {
  name      = "password_repeat"
  field_key = "password_repeat"
  label     = "Confirm Password"
  type      = "password"
  required  = true
  order     = 3
}

resource "authentik_stage_prompt" "enrollment_prompt" {
  name = "ridebase-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.email.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id,
  ]
  validation_policies = []
}

# User write — creates the account as inactive until email is verified
resource "authentik_stage_user_write" "enrollment_user_write" {
  name                     = "ridebase-enrollment-user-write"
  create_users_as_inactive = true
  create_users_group       = authentik_group.ridebase_riders.id
}

# Email OTP verification stage
resource "null_resource" "enrollment_email_stage" {
  triggers = {
    always_run    = timestamp()
    authentik_url = var.authentik_url
    stage_name    = "ridebase-enrollment-email-verify"
  }

  provisioner "local-exec" {
    command = <<EOT
      EXISTING=$(curl -sk \
        -H "Authorization: Bearer ${var.authentik_token}" \
        "${var.authentik_url}/api/v3/stages/email/?name=ridebase-enrollment-email-verify" \
        | jq -r '.results | length')
      if [ "$EXISTING" = "0" ]; then
        curl -sk -X POST \
          -H "Authorization: Bearer ${var.authentik_token}" \
          -H "Content-Type: application/json" \
          -d '{
            "name": "ridebase-enrollment-email-verify",
            "use_global_settings": true,
            "activate_user_on_success": true,
            "subject": "Activate your RideBase account",
            "template": "email/account_confirmation.html",
            "token_expiry": "hours=0;minutes=30;seconds=0"
          }' \
          "${var.authentik_url}/api/v3/stages/email/" | jq .
      else
        echo "Email stage already exists, skipping."
      fi
    EOT
  }
}

# Bind email stage to enrollment flow
resource "null_resource" "enroll_email_binding" {
  depends_on = [null_resource.enrollment_email_stage]

  triggers = {
    always_run = timestamp()
    flow_uuid  = authentik_flow.ridebase_enrollment.uuid
    stage_name = "ridebase-enrollment-email-verify"
  }

  provisioner "local-exec" {
    command = <<EOT
      STAGE_UUID=$(curl -sk \
        -H "Authorization: Bearer ${var.authentik_token}" \
        "${var.authentik_url}/api/v3/stages/email/?name=ridebase-enrollment-email-verify" \
        | jq -r '.results[0].pk')
      echo "Email stage UUID: $STAGE_UUID"
      EXISTING_BINDING=$(curl -sk \
        -H "Authorization: Bearer ${var.authentik_token}" \
        "${var.authentik_url}/api/v3/flows/bindings/?target=${authentik_flow.ridebase_enrollment.uuid}&stage=$STAGE_UUID" \
        | jq -r '.results | length')
      if [ "$EXISTING_BINDING" = "0" ]; then
        curl -sk -X POST \
          -H "Authorization: Bearer ${var.authentik_token}" \
          -H "Content-Type: application/json" \
          -d "{\"target\": \"${authentik_flow.ridebase_enrollment.uuid}\", \"stage\": \"$STAGE_UUID\", \"order\": 20}" \
          "${var.authentik_url}/api/v3/flows/bindings/" | jq .
      else
        echo "Email binding already exists, skipping."
      fi
    EOT
  }
}

# User login stage (shared by both flows)
resource "authentik_stage_user_login" "default_login" {
  name = "ridebase-user-login"
}

resource "authentik_flow_stage_binding" "enroll_prompt" {
  target = authentik_flow.ridebase_enrollment.uuid
  stage  = authentik_stage_prompt.enrollment_prompt.id
  order  = 0
}

resource "authentik_flow_stage_binding" "enroll_user_write" {
  target = authentik_flow.ridebase_enrollment.uuid
  stage  = authentik_stage_user_write.enrollment_user_write.id
  order  = 10
}

resource "authentik_flow_stage_binding" "enroll_login" {
  target = authentik_flow.ridebase_enrollment.uuid
  stage  = authentik_stage_user_login.default_login.id
  order  = 30
}

# ==============================================================================
# RideBase Authentication (Login) Flow
# Flow: identification → password → user_login
# ==============================================================================
resource "authentik_flow" "ridebase_authentication" {
  name        = "ridebase-authentication"
  slug        = "ridebase-authentication"
  title       = "Sign in to RideBase"
  designation = "authentication"
}

# Identification stage — accept username OR email
resource "authentik_stage_identification" "ridebase_identification" {
  name            = "ridebase-identification"
  user_fields     = ["username", "email"]
  enrollment_flow = authentik_flow.ridebase_enrollment.uuid
  sources         = [authentik_source_oauth.google.uuid]
}

# Password stage
resource "authentik_stage_password" "ridebase_password" {
  name     = "ridebase-password"
  backends = ["authentik.core.auth.InbuiltBackend"]
}

# Bind stages to authentication flow
resource "authentik_flow_stage_binding" "auth_identification" {
  target = authentik_flow.ridebase_authentication.uuid
  stage  = authentik_stage_identification.ridebase_identification.id
  order  = 0
}

resource "authentik_flow_stage_binding" "auth_password" {
  target = authentik_flow.ridebase_authentication.uuid
  stage  = authentik_stage_password.ridebase_password.id
  order  = 10
}

resource "authentik_flow_stage_binding" "auth_login" {
  target = authentik_flow.ridebase_authentication.uuid
  stage  = authentik_stage_user_login.default_login.id
  order  = 20
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

# Create a custom scope to inject the user's groups into the JWT
resource "authentik_property_mapping_provider_scope" "groups" {
  name        = "ridebase-scope-groups"
  scope_name  = "groups"
  description = "Injects user groups into the JWT"
  expression  = <<EOF
return {
    "groups": list(set([group.name for group in request.user.ak_groups.all()]))
}
EOF
}

resource "authentik_provider_oauth2" "ridebase" {
  name                = "RideBase Provider"
  client_id           = "ridebase"
  authorization_flow  = data.authentik_flow.default_authorization_flow.id
  invalidation_flow   = data.authentik_flow.default_invalidation_flow.id
  authentication_flow = authentik_flow.ridebase_authentication.uuid
  client_type         = "public"
  allowed_redirect_uris = [
    { matching_mode = "strict", url = "ridebase://callback" }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id, # Added groups injection!
  ]
}

resource "authentik_application" "ridebase" {
  name              = "RideBase"
  slug              = "ridebase"
  protocol_provider = authentik_provider_oauth2.ridebase.id
  open_in_new_tab   = false
}

# ==============================================================================
# Embedded Outpost
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

resource "authentik_policy_binding" "traefik_access" {
  target = authentik_application.traefik.uuid
  group  = data.authentik_group.admins.id
  order  = 0
}
