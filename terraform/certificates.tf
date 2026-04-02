resource "hcloud_managed_certificate" "wildcard" {
  name = "${var.project_name}_wildcard_cert_${var.environment}"
  domain_names = var.environment != "prod" ? [
    var.domain_name,
    "*.${var.domain_name}",
    "*.${var.environment}.${var.domain_name}"
    ] : [
    var.domain_name,
    "*.${var.domain_name}"
  ]
  labels = local.common_labels
  # lifecycle {
  #   prevent_destroy = true
  # }
}
