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

# Custom authorization flow with implicit consent (no prompt).
# The built-in implicit consent flow has internal policies that deny non-superusers.
# This flow auto-approves any authenticated user (including Google SSO users)
# via a consent stage with mode = 0 (always-approve, no user prompt).
resource "authentik_flow" "ridebase_authorization" {
  name               = "ridebase-authorization"
  slug               = "ridebase-authorization"
  title              = "Authorize RideBase"
  designation        = "authorization"
  policy_engine_mode = "any"
}

# Auto-approve consent stage — mode 0 means "always approve" (no prompt shown)
# Without this, the authorization flow has no stages and Authentik cannot
# complete the OAuth handshake, causing redirect to the portal instead of
# ridebase://callback.
resource "authentik_stage_consent" "ridebase_auto_approve" {
  name = "ridebase-auto-approve-consent"
  mode = "permanent"
}

resource "authentik_flow_stage_binding" "authorization_consent" {
  target = authentik_flow.ridebase_authorization.uuid
  stage  = authentik_stage_consent.ridebase_auto_approve.id
  order  = 0
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# ==============================================================================
# RideBase Invalidation (Logout) Flow
# Properly clears the user session so logout actually works.
# The default-provider-invalidation-flow only does OIDC back-channel logout
# and does NOT destroy the Authentik session cookie.
# ==============================================================================
resource "authentik_flow" "ridebase_invalidation" {
  name        = "ridebase-invalidation"
  slug        = "ridebase-invalidation"
  title       = "Signed Out"
  designation = "invalidation"
  layout      = "stacked"
}

resource "authentik_stage_user_logout" "ridebase_logout" {
  name = "ridebase-user-logout"
}

resource "authentik_flow_stage_binding" "invalidation_logout" {
  target = authentik_flow.ridebase_invalidation.uuid
  stage  = authentik_stage_user_logout.ridebase_logout.id
  order  = 0
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

# --- Anti-takeover: only link Google to accounts that verified their email ---
# Without this, an attacker can pre-register victim@gmail.com (unverified)
# and Authentik's email_link mode silently links the real Google owner
# to the attacker's account.
# Bound to the Google enrollment flow (not source auth) so it runs during
# account creation only.

resource "authentik_policy_expression" "require_email_verified_for_link" {
  name       = "ridebase-require-email-verified-for-link"
  expression = <<-EXPR
    # Prevent pre-registration takeover attacks.
    # If a Google user's email matches an unverified account, delete the
    # squatter so the real owner gets a fresh account via Google enrollment.
    # Unverified accounts can't take rides or transact, so no data is lost.
    # NEVER delete superusers — they are trusted admin accounts.
    # NEVER delete users who already have an OAuth source connection
    # (they signed up via Google previously — let them log in).
    from authentik.sources.oauth.models import UserOAuthSourceConnection
    pending_user = request.context.get("pending_user")
    if pending_user:
        if pending_user.ak_groups.filter(is_superuser=True).exists():
            return True
        if pending_user.attributes.get("email_verified", False) == True:
            return True
        # If user already has a Google source connection, they're legit
        if UserOAuthSourceConnection.objects.filter(user=pending_user).exists():
            return True
        # Unverified squatter — wipe it so Google enrollment creates a clean account
        pending_user.delete()
        return True
    # No existing account — allow (will create via enrollment flow)
    return True
  EXPR
}

# Use Authentik's built-in default source authentication flow.
# Custom source auth flows lose the pending OAuth authorize context,
# causing the redirect to ridebase://callback to fail.
data "authentik_flow" "default_source_authentication" {
  slug = "default-source-authentication"
}

resource "authentik_flow" "google_enrollment" {
  name        = "ridebase-google-enrollment"
  slug        = "ridebase-google-enrollment"
  title       = "Sign Up with Google"
  designation = "enrollment"
  layout      = "stacked"
}

# 1. Custom Google Enrollment Prompt (Asks for Username)
resource "authentik_stage_prompt" "google_enrollment_prompt" {
  name = "ridebase-google-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.username.id
  ]
  validation_policies = [
    authentik_policy_expression.ridebase_username_policy.id,
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
  user_type                = "internal"
}

resource "authentik_flow_stage_binding" "google_enroll_write" {
  target = authentik_flow.google_enrollment.uuid
  stage  = authentik_stage_user_write.google_user_write.id
  order  = 10
}

# NOTE: No user_login stage here — login is handled by the built-in
# default-source-authentication flow, which preserves OAuth context.

# Bind anti-takeover policy to enrollment flow
resource "authentik_policy_binding" "google_enroll_require_verified" {
  target = authentik_flow.google_enrollment.uuid
  policy = authentik_policy_expression.require_email_verified_for_link.id
  order  = 0
}

resource "authentik_source_oauth" "google" {
  name                = "Sign in with Google"
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
  title       = "Create Account"
  designation = "enrollment"
  layout      = "stacked"
}

# Subtitle
resource "authentik_stage_prompt_field" "enrollment_subtitle" {
  name          = "enrollment-subtitle"
  field_key     = "enrollment_subtitle"
  label         = "Sign up to get started with Ridebase"
  type          = "static"
  required      = false
  order         = -1
  initial_value = "Sign up to get started with Ridebase"
}

# Prompt fields
resource "authentik_stage_prompt_field" "email" {
  name        = "email"
  field_key   = "email"
  label       = "Email"
  type        = "email"
  required    = true
  placeholder = "you@example.com"
  order       = 0
}

resource "authentik_stage_prompt_field" "username" {
  name        = "username"
  field_key   = "username"
  label       = "Username"
  type        = "username"
  required    = true
  placeholder = "Choose a username"
  order       = 1
}

resource "authentik_stage_prompt_field" "password" {
  name        = "password"
  field_key   = "password"
  label       = "Password"
  type        = "password"
  required    = true
  placeholder = "Create a password"
  order       = 2
}

resource "authentik_stage_prompt_field" "password_repeat" {
  name        = "password_repeat"
  field_key   = "password_repeat"
  label       = "Confirm Password"
  type        = "password"
  required    = true
  placeholder = "Confirm your password"
  order       = 3
}

# Username policy — enforces platform-quality usernames
# Rules based on GitHub/Instagram/Discord conventions:
#   - 3–20 characters
#   - Must start with a letter
#   - Only lowercase letters, numbers, underscores, periods
#   - No spaces, no consecutive special chars (__  ..)
#   - Cannot end with underscore or period
#   - Cannot be purely numeric
#   - Blocks reserved/system names
resource "authentik_policy_expression" "ridebase_username_policy" {
  name       = "ridebase-username-policy"
  expression = <<-EXPR
    import re
    username = request.context.get("prompt_data", {}).get("username", "")
    if not username:
        ak_message("Username is required.")
        return False
    # Normalise to lowercase (Authentik stores lowercase anyway)
    username = username.strip()
    if len(username) < 3:
        ak_message("Username must be at least 3 characters.")
        return False
    if len(username) > 20:
        ak_message("Username cannot be longer than 20 characters.")
        return False
    if " " in username:
        ak_message("Username cannot contain spaces.")
        return False
    if not re.match(r'^[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]$', username) and len(username) >= 3:
        ak_message("Username must start with a letter, end with a letter or number, and contain only letters, numbers, underscores, or periods.")
        return False
    if '..' in username or '__' in username or '._' in username or '_.' in username:
        ak_message("Username cannot have consecutive special characters.")
        return False
    if username.isdigit():
        ak_message("Username cannot be only numbers.")
        return False
    reserved = {"admin", "administrator", "root", "system", "support", "help",
                "ridebase", "driver", "rider", "moderator", "mod", "staff",
                "official", "security", "api", "null", "undefined", "test"}
    if username.lower() in reserved:
        ak_message("That username is reserved. Please choose another.")
        return False
    return True
  EXPR
}

# Password complexity policy — minimum 8 chars with at least 1 number
resource "authentik_policy_password" "ridebase_password_policy" {
  name          = "ridebase-password-policy"
  length_min    = 8
  amount_digits = 1
  error_message = "Password must be at least 8 characters with at least 1 number."
}

resource "authentik_stage_prompt" "enrollment_prompt" {
  name = "ridebase-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.enrollment_subtitle.id,
    authentik_stage_prompt_field.email.id,
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id,
  ]
  validation_policies = [
    authentik_policy_password.ridebase_password_policy.id,
    authentik_policy_expression.ridebase_username_policy.id,
  ]
}

# User write — creates the account as active immediately
# user_type = internal so users can interact with the SSO web interface
# (login, consent). This does NOT grant admin access — group policies
# control application access.
resource "authentik_stage_user_write" "enrollment_user_write" {
  name                     = "ridebase-enrollment-user-write"
  create_users_as_inactive = false
  create_users_group       = authentik_group.ridebase_riders.id
  user_type                = "internal"
}

# Email OTP verification stage
# Email stage removed — email OTP verification is now handled
# by the onboarding service after sign-up (not in the Authentik flow).
# To clean up the existing stage+binding from Authentik, run:
#   curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" \
#     "$AUTH_URL/api/v3/stages/email/?name=ridebase-enrollment-email-verify"

# User login stage (used by authentication flow only)
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

# NOTE: No user_login stage in enrollment. When enrollment is triggered from
# an OAuth /authorize request, adding user_login creates a new session that
# destroys the pending OAuth context (PKCE, redirect_uri). Without it,
# enrollment completes → user is redirected back to the authentication flow
# → enters their (freshly created) credentials → user_login → OAuth authorize
# → consent → ridebase://callback.

# ==============================================================================
# RideBase Authentication (Login) Flow
# Flow: identification → password → user_login
# ==============================================================================
resource "authentik_flow" "ridebase_authentication" {
  name        = "ridebase-authentication"
  slug        = "ridebase-authentication"
  title       = "Welcome Back"
  designation = "authentication"
  layout      = "stacked"
}

# Identification stage — accept username OR email
resource "authentik_stage_identification" "ridebase_identification" {
  name               = "ridebase-identification"
  user_fields        = ["username", "email"]
  enrollment_flow    = authentik_flow.ridebase_enrollment.uuid
  sources            = [authentik_source_oauth.google.uuid]
  show_source_labels = true
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

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

# Custom scope to inject the user's numeric PK into the JWT
# Piggybacks on the "profile" scope so no client changes are needed
resource "authentik_property_mapping_provider_scope" "user_pk" {
  name        = "ridebase-scope-user-pk"
  scope_name  = "profile"
  description = "Injects user numeric PK into the JWT for API calls"
  expression  = <<EOF
return {
    "authentik_pk": request.user.pk
}
EOF
}

# Custom scope to inject is_subscribed boolean into the JWT
# This attribute is set by the payment service via the Authentik API
resource "authentik_property_mapping_provider_scope" "subscription" {
  name        = "ridebase-scope-subscription"
  scope_name  = "profile"
  description = "Injects driver subscription status (is_subscribed) into the JWT"
  expression  = <<EOF
return {
    "is_subscribed": request.user.attributes.get("is_subscribed", False)
}
EOF
}

# Custom scope to inject email_verified boolean into the JWT
# This attribute is set by the onboarding service via the Authentik API
# after the user verifies their email with a 6-digit OTP
resource "authentik_property_mapping_provider_scope" "email_verified" {
  name        = "ridebase-scope-email-verified"
  scope_name  = "profile"
  description = "Injects email verification status (email_verified) into the JWT"
  expression  = <<EOF
return {
    "email_verified": request.user.attributes.get("email_verified", False)
}
EOF
}

resource "authentik_provider_oauth2" "ridebase" {
  name                = "RideBase Provider"
  client_id           = "ridebase"
  authorization_flow  = authentik_flow.ridebase_authorization.uuid
  invalidation_flow   = authentik_flow.ridebase_invalidation.uuid
  authentication_flow = authentik_flow.ridebase_authentication.uuid
  client_type         = "public"
  signing_key         = data.authentik_certificate_key_pair.default.id
  allowed_redirect_uris = [
    { matching_mode = "strict", url = "ridebase://callback" },
    { matching_mode = "strict", url = "ridebase://logout-callback" }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.offline_access.id,
    authentik_property_mapping_provider_scope.subscription.id,
    authentik_property_mapping_provider_scope.user_pk.id,
    authentik_property_mapping_provider_scope.email_verified.id,
  ]
}

resource "authentik_application" "ridebase" {
  name               = "RideBase"
  slug               = "ridebase"
  protocol_provider  = authentik_provider_oauth2.ridebase.id
  open_in_new_tab    = false
  policy_engine_mode = "any"
}

# Allow riders — default group for all sign-ups (username/password + Google)
resource "authentik_policy_binding" "ridebase_riders_access" {
  target = authentik_application.ridebase.uuid
  group  = authentik_group.ridebase_riders.id
  order  = 0
}

# Allow drivers
resource "authentik_policy_binding" "ridebase_drivers_access" {
  target = authentik_application.ridebase.uuid
  group  = authentik_group.ridebase_drivers.id
  order  = 1
}

# Allow admins (for testing/support)
resource "authentik_policy_binding" "ridebase_admins_access" {
  target = authentik_application.ridebase.uuid
  group  = data.authentik_group.admins.id
  order  = 2
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

# ==============================================================================
# RideBase Brand Customization
# ==============================================================================
resource "authentik_brand" "ridebase" {
  domain              = "auth.${local.env_subdomain}${var.domain_name}"
  default             = false
  branding_title      = "RideBase"
  branding_logo       = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon    = "/static/dist/assets/icons/icon.png"
  flow_authentication = authentik_flow.ridebase_authentication.uuid
  flow_invalidation   = authentik_flow.ridebase_invalidation.uuid

  attributes = jsonencode({
    settings = {
      theme = {
        base = "dark"
      }
    }
  })
}

locals {
  ridebase_css = <<-CSS
    /* RideBase brand — Kinetic Anchor design system */
    /* Primary: #004444, Background: #F8FAFA */
    /* ALL rules scoped under .pf-c-login so admin dashboard stays default */
    /* NOTE: @import is not supported in adoptedStyleSheets — use system font stack */

    /* Page background — only on login pages */
    .pf-c-login {
      background: #F8FAFA !important;
      background-color: #F8FAFA !important;
      color: #191C1D !important;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
    }

    /* Hide default background image */
    .pf-c-login .pf-c-background-image {
      display: none !important;
    }

    /* Card / main form area */
    .pf-c-login .pf-c-login__main,
    .pf-c-login .ak-login-container {
      background-color: #ffffff !important;
      color: #191C1D !important;
      border-radius: 16px !important;
      box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08) !important;
    }

    /* Restyle the Authentik logo as teal car circle */
    .pf-c-login .pf-c-login__header {
      display: flex !important;
      justify-content: center !important;
      padding: 24px 0 8px !important;
    }
    .pf-c-login .pf-c-login__header img.pf-c-brand,
    .pf-c-login img[src*="icon_left_brand"] {
      width: 80px !important;
      height: 80px !important;
      padding: 0 !important;
      border-radius: 50% !important;
      background-color: #004444 !important;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 512 512'%3E%3Cpath fill='%23fff' d='M135.2 117.4L109.1 192H402.9l-26.1-74.6C372.3 104.6 360.2 96 346.6 96H165.4c-13.6 0-25.7 8.6-30.2 21.4zM39.6 196.8L74.8 96.3C88.3 57.8 124.6 32 165.4 32h181.2c40.8 0 77.1 25.8 90.6 64.3l35.2 100.5c23.2 9.6 39.6 32.5 39.6 59.2v96c0 17.7-14.3 32-32 32h-32c-17.7 0-32-14.3-32-32v-32H96v32c0 17.7-14.3 32-32 32H32c-17.7 0-32-14.3-32-32v-96c0-26.7 16.4-49.6 39.6-59.2zM128 288a32 32 0 1 0-64 0 32 32 0 1 0 64 0zm288 32a32 32 0 1 0 0-64 32 32 0 1 0 0 64z'/%3E%3C/svg%3E") !important;
      background-size: 40px 40px !important;
      background-repeat: no-repeat !important;
      background-position: center !important;
      content: '' !important;
      font-size: 0 !important;
      color: transparent !important;
      overflow: hidden !important;
      object-position: -9999px !important;
    }

    /* Flow title & headings — centered */
    .pf-c-login .pf-c-login__main-header,
    .pf-c-login .ak-flow-header,
    .pf-c-login [slot="header"] {
      text-align: center !important;
    }
    .pf-c-login .pf-c-login__main-header p,
    .pf-c-login .pf-c-login__main-header-desc,
    .pf-c-login .pf-c-login__main-header .pf-c-content p,
    .pf-c-login .pf-c-login__main-body p:first-of-type {
      text-align: center !important;
      display: block !important;
      width: 100% !important;
      font-size: 16px !important;
      font-weight: 400 !important;
      color: #6B7280 !important;
    }

    /* Style the static subtitle field on enrollment */
    .pf-c-login .pf-c-form__group:first-child {
      text-align: center !important;
    }
    .pf-c-login .pf-c-form__group:first-child .pf-c-form__label,
    .pf-c-login .pf-c-form__group:first-child .pf-c-form__label-text {
      text-align: center !important;
      display: block !important;
      width: 100% !important;
      font-size: 16px !important;
      font-weight: 400 !important;
      color: #6B7280 !important;
      margin-bottom: 8px !important;
    }

    /* Flow title & headings */
    .pf-c-login .pf-c-title,
    .pf-c-login h1,
    .pf-c-login h2,
    .pf-c-login h3 {
      color: #191C1D !important;
      font-weight: 700 !important;
    }

    /* Primary buttons — teal pill */
    .pf-c-login .pf-c-button.pf-m-primary,
    .pf-c-login button[class*="primary"] {
      background-color: #004444 !important;
      border-color: #004444 !important;
      border-radius: 24px !important;
      color: #ffffff !important;
      font-weight: 600 !important;
      min-height: 52px !important;
    }
    .pf-c-login .pf-c-button.pf-m-primary:hover,
    .pf-c-login button[class*="primary"]:hover {
      background-color: #003636 !important;
      border-color: #003636 !important;
    }

    /* Links */
    .pf-c-login .pf-c-button.pf-m-link,
    .pf-c-login a {
      color: #004444 !important;
    }
    .pf-c-login a:hover {
      color: #003636 !important;
    }

    /* ── Social login sources ── */
    /* "or" divider above the source buttons */
    .pf-c-login .pf-c-login__main-footer::before {
      content: 'or' !important;
      display: flex !important;
      align-items: center !important;
      justify-content: center !important;
      width: 100% !important;
      font-size: 14px !important;
      color: #9CA3AF !important;
      margin: 8px 0 !important;
      gap: 12px !important;
      background-image: linear-gradient(#E5E7EB, #E5E7EB), linear-gradient(#E5E7EB, #E5E7EB) !important;
      background-size: calc(50% - 24px) 1px, calc(50% - 24px) 1px !important;
      background-position: left center, right center !important;
      background-repeat: no-repeat !important;
    }

    /* Source list fieldset — remove default fieldset chrome */
    fieldset[name="login-sources"] {
      border: none !important;
      padding: 0 !important;
      margin: 0 !important;
      width: 100% !important;
      display: block !important;
    }
    fieldset[name="login-sources"] legend {
      display: none !important;
    }

    /* Source button — the actual Google button is <button class="pf-c-button source-button"> */
    button.source-button,
    button[name="source-google"] {
      display: flex !important;
      flex-wrap: nowrap !important;
      align-items: center !important;
      justify-content: center !important;
      gap: 10px !important;
      width: 100% !important;
      box-sizing: border-box !important;
      padding: 14px 16px !important;
      background-color: #ffffff !important;
      border: 2px solid #004444 !important;
      border-radius: 24px !important;
      color: #191C1D !important;
      font-weight: 600 !important;
      font-size: 16px !important;
      min-height: 52px !important;
      cursor: pointer !important;
      transition: background-color 0.15s ease, border-color 0.15s ease !important;
    }
    button.source-button:hover,
    button[name="source-google"]:hover {
      background-color: #F0F3F3 !important;
      border-color: #003636 !important;
    }

    /* Source button icon — override dark theme filter so Google colors show */
    button.source-button img,
    button[name="source-google"] img {
      width: 28px !important;
      height: 28px !important;
      display: inline-block !important;
      visibility: visible !important;
      opacity: 1 !important;
      filter: brightness(1) invert(0) !important;
      -webkit-filter: brightness(1) invert(0) !important;
    }

    /* Source button label text (show_source_labels = true renders a <span>) */
    button.source-button span,
    button[name="source-google"] span {
      color: #191C1D !important;
      font-size: 16px !important;
      font-weight: 600 !important;
    }

    /* Labels and body text — NOT matching button spans */
    .pf-c-login label,
    .pf-c-login .pf-c-form__label,
    .pf-c-login .pf-c-form__label-text,
    .pf-c-login p {
      color: #6B7280 !important;
      font-size: 14px !important;
    }

    /* Input fields — filled gray with teal underline */
    .pf-c-login .pf-c-form-control,
    .pf-c-login input,
    .pf-c-login input[type="text"],
    .pf-c-login input[type="email"],
    .pf-c-login input[type="password"] {
      background-color: #F0F3F3 !important;
      color: #191C1D !important;
      border: none !important;
      border-bottom: 2px solid #004444 !important;
      border-radius: 4px !important;
      padding: 14px 16px !important;
      outline: none !important;
      box-shadow: none !important;
    }
    .pf-c-login .pf-c-form-control::after,
    .pf-c-login .pf-c-form-control::before {
      border-bottom-color: #004444 !important;
    }
    .pf-c-login .pf-c-form-control:focus,
    .pf-c-login input:focus {
      border-bottom: 2px solid #004444 !important;
      box-shadow: none !important;
      outline: none !important;
    }

    /* Hide language selector */
    .pf-c-login .pf-c-select,
    .pf-c-login select[name="locale"],
    .pf-c-login .ak-locale-select,
    .pf-c-login [aria-label="locale"],
    ak-locale-context,
    [aria-label="locale"] {
      display: none !important;
    }

    /* Ensure social login footer is visible */
    .pf-c-login .pf-c-login__main-footer,
    .pf-c-login__main-footer {
      display: block !important;
      visibility: visible !important;
      height: auto !important;
      overflow: visible !important;
    }

    /* Hide "Powered by authentik" site footer */
    footer[name="site-footer"],
    footer.pf-c-login__footer,
    footer[aria-label="Site footer"] {
      display: none !important;
    }
  CSS
}

# Inject custom CSS via Authentik API (TF provider lacks branding_custom_css attribute)
resource "null_resource" "ridebase_brand_css" {
  depends_on = [authentik_brand.ridebase]

  triggers = {
    css_hash   = sha256(local.ridebase_css)
    brand_hash = sha256(jsonencode(authentik_brand.ridebase))
  }

  provisioner "local-exec" {
    command = <<-EOT
      BRAND_ID=$(curl -sk \
        -H "Authorization: Bearer ${var.authentik_token}" \
        "${var.authentik_url}/api/v3/core/brands/?domain=auth.${local.env_subdomain}${var.domain_name}" \
        | jq -r '.results[0].brand_uuid')

      echo "Patching brand $BRAND_ID with custom CSS..."

      cat <<'CSSEOF' > /tmp/ridebase_brand_css.json
${jsonencode({ "branding_custom_css" = local.ridebase_css })}
CSSEOF

      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.authentik_token}" \
        -H "Content-Type: application/json" \
        -d @/tmp/ridebase_brand_css.json \
        "${var.authentik_url}/api/v3/core/brands/$BRAND_ID/" | jq .

      rm -f /tmp/ridebase_brand_css.json
    EOT
  }
}
