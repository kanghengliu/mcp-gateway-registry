# Secrets Manager resources for MCP Gateway Registry

# Random passwords for application secrets

resource "random_password" "secret_key" {
  length  = 64
  special = true
}

resource "random_password" "admin_password" {
  length      = 32
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# Random passwords for Keycloak
resource "random_password" "keycloak_postgres_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "random_password" "keycloak_admin_password" {
  length      = 32
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# Core application secrets

resource "aws_secretsmanager_secret" "secret_key" {
  name_prefix = "${local.name_prefix}-secret-key-"
  description = "Secret key for MCP Gateway Registry"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "secret_key" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = random_password.secret_key.result
}

resource "aws_secretsmanager_secret" "admin_password" {
  name_prefix = "${local.name_prefix}-admin-password-"
  description = "Admin password for MCP Gateway Registry"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "admin_password" {
  secret_id     = aws_secretsmanager_secret.admin_password.id
  secret_string = random_password.admin_password.result
}

# Keycloak database secrets
resource "aws_secretsmanager_secret" "keycloak_database_url" {
  name_prefix = "${local.name_prefix}-keycloak-database-url-"
  description = "Database URL for Keycloak PostgreSQL"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_database_url" {
  secret_id = aws_secretsmanager_secret.keycloak_database_url.id
  secret_string = "postgresql://${module.aurora_postgresql.cluster_master_username}:${module.aurora_postgresql.cluster_master_password}@${module.aurora_postgresql.cluster_endpoint}:${module.aurora_postgresql.cluster_port}/${module.aurora_postgresql.cluster_database_name}"
}

resource "aws_secretsmanager_secret" "keycloak_db_password" {
  name_prefix = "${local.name_prefix}-keycloak-db-password-"
  description = "Database password for Keycloak PostgreSQL"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_db_password" {
  secret_id     = aws_secretsmanager_secret.keycloak_db_password.id
  secret_string = random_password.keycloak_postgres_password.result
}

resource "aws_secretsmanager_secret" "keycloak_admin_password" {
  name_prefix = "${local.name_prefix}-keycloak-admin-password-"
  description = "Admin password for Keycloak"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_admin_password" {
  secret_id     = aws_secretsmanager_secret.keycloak_admin_password.id
  secret_string = random_password.keycloak_admin_password.result
}

# Keycloak Secrets (conditional)
resource "aws_secretsmanager_secret" "keycloak_client_secret" {
  count       = var.keycloak_client_secret != "" ? 1 : 0
  name_prefix = "${local.name_prefix}-keycloak-client-secret-"
  description = "Keycloak client secret for MCP Gateway Registry"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_client_secret" {
  count         = var.keycloak_client_secret != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.keycloak_client_secret[0].id
  secret_string = var.keycloak_client_secret
}

resource "aws_secretsmanager_secret" "keycloak_m2m_client_secret" {
  count       = var.keycloak_m2m_client_secret != "" ? 1 : 0
  name_prefix = "${local.name_prefix}-keycloak-m2m-client-secret-"
  description = "Keycloak M2M client secret for MCP Gateway Registry"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "keycloak_m2m_client_secret" {
  count         = var.keycloak_m2m_client_secret != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.keycloak_m2m_client_secret[0].id
  secret_string = var.keycloak_m2m_client_secret
}