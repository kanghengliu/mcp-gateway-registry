# Root Module Outputs

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# ECS Cluster Outputs
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.arn
}

# MCP Gateway Outputs
output "mcp_gateway_url" {
  description = "MCP Gateway main URL"
  value       = module.mcp_gateway.service_urls.registry
}

output "mcp_gateway_auth_url" {
  description = "MCP Gateway auth server URL"
  value       = module.mcp_gateway.service_urls.auth
}

output "mcp_gateway_keycloak_url" {
  description = "MCP Gateway Keycloak URL"
  value       = module.mcp_gateway.service_urls.keycloak
}

output "mcp_gateway_alb_dns" {
  description = "MCP Gateway ALB DNS name"
  value       = module.mcp_gateway.alb_dns_name
}

output "mcp_gateway_https_enabled" {
  description = "Whether HTTPS is enabled for MCP Gateway"
  value       = module.mcp_gateway.https_enabled
}

output "mcp_gateway_autoscaling_enabled" {
  description = "Whether auto-scaling is enabled for MCP Gateway"
  value       = module.mcp_gateway.autoscaling_enabled
}

output "mcp_gateway_monitoring_enabled" {
  description = "Whether monitoring is enabled for MCP Gateway"
  value       = module.mcp_gateway.monitoring_enabled
}

# Monitoring Outputs
output "monitoring_sns_topic" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = var.enable_monitoring ? module.mcp_gateway.sns_topic_arn : null
}

# Summary Output
output "deployment_summary" {
  description = "Summary of deployed components"
  value = {
    mcp_gateway_deployed = true
    https_enabled        = var.certificate_arn != ""
    monitoring_enabled   = var.enable_monitoring
    multi_az_nat         = true
    autoscaling_enabled  = true
  }
}
