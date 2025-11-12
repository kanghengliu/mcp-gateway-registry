# MCP Gateway Registry Module Outputs

# Keycloak Database outputs
output "keycloak_database_endpoint" {
  description = "Keycloak PostgreSQL cluster endpoint"
  value       = module.aurora_postgresql.cluster_endpoint
  sensitive   = false
}

output "keycloak_database_port" {
  description = "Keycloak PostgreSQL cluster port"
  value       = module.aurora_postgresql.cluster_port
  sensitive   = false
}

output "keycloak_database_name" {
  description = "Keycloak PostgreSQL database name"
  value       = module.aurora_postgresql.cluster_database_name
  sensitive   = false
}

output "keycloak_database_username" {
  description = "Keycloak PostgreSQL cluster master username"
  value       = module.aurora_postgresql.cluster_master_username
  sensitive   = false
}

# Main ALB outputs
output "alb_dns_name" {
  description = "DNS name of the MCP Gateway Registry ALB"
  value       = module.alb.dns_name
  sensitive   = false
}

output "alb_zone_id" {
  description = "Zone ID of the MCP Gateway Registry ALB"
  value       = module.alb.zone_id
  sensitive   = false
}

output "alb_arn" {
  description = "ARN of the MCP Gateway Registry ALB"
  value       = module.alb.arn
  sensitive   = false
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = module.alb.security_group_id
  sensitive   = false
}

# Keycloak ALB outputs
output "keycloak_alb_dns_name" {
  description = "DNS name of the Keycloak ALB"
  value       = module.keycloak_alb.dns_name
  sensitive   = false
}

output "keycloak_alb_zone_id" {
  description = "Zone ID of the Keycloak ALB"
  value       = module.keycloak_alb.zone_id
  sensitive   = false
}

output "keycloak_alb_arn" {
  description = "ARN of the Keycloak ALB"
  value       = module.keycloak_alb.arn
  sensitive   = false
}

output "keycloak_alb_security_group_id" {
  description = "ID of the Keycloak ALB security group"
  value       = module.keycloak_alb.security_group_id
  sensitive   = false
}

# Service URLs
output "service_urls" {
  description = "URLs for MCP Gateway Registry services"
  value = {
    registry = var.domain_name != "" ? "https://${var.domain_name}" : "http://${module.alb.dns_name}"
    auth     = var.domain_name != "" ? "https://${var.domain_name}:8888" : "http://${module.alb.dns_name}:8888"
    gradio   = var.domain_name != "" ? "https://${var.domain_name}:7860" : "http://${module.alb.dns_name}:7860"
    keycloak = "http://${module.keycloak_alb.dns_name}:8080"  # Always use internal ALB for Keycloak
  }
  sensitive = false
}

# EFS outputs
output "efs_id" {
  description = "MCP Gateway Registry EFS file system ID"
  value       = module.efs.id
  sensitive   = false
}

output "efs_arn" {
  description = "MCP Gateway Registry EFS file system ARN"
  value       = module.efs.arn
  sensitive   = false
}

output "efs_access_points" {
  description = "EFS access point IDs"
  value = {
    servers = module.efs.access_points["servers"].id
    models  = module.efs.access_points["models"].id
    logs    = module.efs.access_points["logs"].id
  }
  sensitive   = false
}

# Service Discovery outputs
output "service_discovery_namespace_id" {
  description = "MCP Gateway Registry service discovery namespace ID"
  value       = aws_service_discovery_private_dns_namespace.mcp.id
  sensitive   = false
}

output "service_discovery_namespace_arn" {
  description = "MCP Gateway Registry service discovery namespace ARN"
  value       = aws_service_discovery_private_dns_namespace.mcp.arn
  sensitive   = false
}

# Secrets Manager outputs
output "secret_arns" {
  description = "ARNs of MCP Gateway Registry secrets"
  value = merge({
    secret_key                = aws_secretsmanager_secret.secret_key.arn
    admin_password           = aws_secretsmanager_secret.admin_password.arn
    keycloak_database_url    = aws_secretsmanager_secret.keycloak_database_url.arn
    keycloak_db_password     = aws_secretsmanager_secret.keycloak_db_password.arn
    keycloak_admin_password  = aws_secretsmanager_secret.keycloak_admin_password.arn
  },
  var.keycloak_client_secret != "" ? {
    keycloak_client_secret = aws_secretsmanager_secret.keycloak_client_secret[0].arn
  } : {},
  var.keycloak_m2m_client_secret != "" ? {
    keycloak_m2m_client_secret = aws_secretsmanager_secret.keycloak_m2m_client_secret[0].arn
  } : {})
  sensitive = false
}

# ECS Service outputs
output "ecs_service_arns" {
  description = "ARNs of the ECS services"
  value = {
    auth     = module.ecs_service_auth.id
    registry = module.ecs_service_registry.id
    keycloak = module.ecs_service_keycloak.id
  }
  sensitive = false
}

output "ecs_service_names" {
  description = "Names of the ECS services"
  value = {
    auth     = module.ecs_service_auth.name
    registry = module.ecs_service_registry.name
    keycloak = module.ecs_service_keycloak.name
  }
  sensitive = false
}

# Security Group outputs
output "ecs_security_group_ids" {
  description = "Security group IDs for ECS services"
  value = {
    auth     = module.ecs_service_auth.security_group_id
    registry = module.ecs_service_registry.security_group_id
    keycloak = module.ecs_service_keycloak.security_group_id
    efs      = module.efs.security_group_id
  }
  sensitive = false
}

# Admin credentials output (for initial setup)
output "admin_credentials" {
  description = "Admin credentials for initial MCP Gateway Registry setup"
  value = {
    username = "admin"
    # Note: Password is stored in AWS Secrets Manager
    password_secret_arn = aws_secretsmanager_secret.admin_password.arn
  }
  sensitive = false
}

# Keycloak admin credentials output
output "keycloak_admin_credentials" {
  description = "Keycloak admin credentials for initial setup"
  value = {
    username = var.keycloak_admin_username
    # Note: Password is stored in AWS Secrets Manager
    password_secret_arn = aws_secretsmanager_secret.keycloak_admin_password.arn
  }
  sensitive = false
}

# Monitoring outputs
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

output "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = var.enable_monitoring && var.alarm_email != "" ? module.sns_alarms.topic_arn : null
}

output "autoscaling_enabled" {
  description = "Whether auto-scaling is enabled"
  value       = var.enable_autoscaling
}

output "https_enabled" {
  description = "Whether HTTPS is enabled"
  value       = var.certificate_arn != ""
}