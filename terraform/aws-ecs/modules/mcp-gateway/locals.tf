# Local values for MCP Gateway Registry Module

locals {
  name_prefix = var.name

  common_tags = merge(
    {
      stack        = var.name
      component    = "mcp-gateway-registry"
    },
    var.additional_tags
  )

  # Keycloak secret ARNs for IAM policies
  keycloak_secret_arns = compact([
    aws_secretsmanager_secret.keycloak_database_url.arn,
    aws_secretsmanager_secret.keycloak_db_password.arn,
    aws_secretsmanager_secret.keycloak_admin_password.arn,
    var.keycloak_client_secret != "" ? aws_secretsmanager_secret.keycloak_client_secret[0].arn : "",
    var.keycloak_m2m_client_secret != "" ? aws_secretsmanager_secret.keycloak_m2m_client_secret[0].arn : "",
  ])
}