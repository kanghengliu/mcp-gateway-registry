# MCP Gateway Registry Module Variables

# Required Variables - Shared Resources
variable "name" {
  description = "Name prefix for MCP Gateway Registry resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS services"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ARN of the existing ECS cluster"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the existing ECS cluster"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the task execution IAM role (DEPRECATED: Module now creates its own task execution roles)"
  type        = string
  default     = ""
}

# Container Image URIs (pre-built images from Docker Hub)
variable "registry_image_uri" {
  description = "Container image URI for registry service (defaults to pre-built image from mcpgateway Docker Hub)"
  type        = string
  default     = "mcpgateway/registry:latest"
}

variable "auth_server_image_uri" {
  description = "Container image URI for auth server service (defaults to pre-built image from mcpgateway Docker Hub)"
  type        = string
  default     = "mcpgateway/auth-server:latest"
}

variable "keycloak_image_uri" {
  description = "Container image URI for Keycloak service (defaults to official Keycloak image, mirrored at mcpgateway/keycloak)"
  type        = string
  default     = "mcpgateway/keycloak:latest"
}

variable "dockerhub_org" {
  description = "Docker Hub organization for pre-built images"
  type        = string
  default     = "mcpgateway"
}


# Resource Configuration
variable "cpu" {
  description = "CPU allocation for MCP Gateway Registry containers (in vCPU units: 256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "1024"
  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096"], var.cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

variable "memory" {
  description = "Memory allocation for MCP Gateway Registry containers (in MB, must be compatible with CPU)"
  type        = string
  default     = "2048"
}

variable "registry_replicas" {
  description = "Number of replicas for MCP Gateway Registry main service"
  type        = number
  default     = 1
  validation {
    condition     = var.registry_replicas > 0
    error_message = "Registry replicas must be greater than 0."
  }
}

variable "auth_replicas" {
  description = "Number of replicas for MCP Gateway Auth service"
  type        = number
  default     = 1
  validation {
    condition     = var.auth_replicas > 0
    error_message = "Auth replicas must be greater than 0."
  }
}

variable "keycloak_replicas" {
  description = "Number of replicas for Keycloak service"
  type        = number
  default     = 1
  validation {
    condition     = var.keycloak_replicas > 0
    error_message = "Keycloak replicas must be greater than 0."
  }
}

# Database Configuration (Keycloak only)
variable "postgres_version" {
  description = "PostgreSQL engine version to use"
  type        = string
  default     = "15.5"
}

variable "keycloak_postgres_min_capacity" {
  description = "Minimum ACU capacity for Keycloak PostgreSQL Serverless v2"
  type        = number
  default     = 0.5
}

variable "keycloak_postgres_max_capacity" {
  description = "Maximum ACU capacity for Keycloak PostgreSQL Serverless v2"
  type        = number
  default     = 1.0
}

variable "keycloak_db_name" {
  description = "Database name for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_db_username" {
  description = "Database username for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

# ALB Configuration
variable "alb_scheme" {
  description = "Scheme for the ALB (internal or internet-facing)"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["internal", "internet-facing"], var.alb_scheme)
    error_message = "ALB scheme must be either 'internal' or 'internet-facing'."
  }
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Keycloak Configuration
variable "keycloak_url" {
  description = "Keycloak server URL (deprecated - now uses internal ALB automatically)"
  type        = string
  default     = ""
}

variable "keycloak_ingress_cidr" {
  description = "CIDR block allowed to access Keycloak ALB (typically VPC CIDR)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "enable_autoscaling" {
  description = "Whether to enable auto-scaling for ECS services"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 2
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 4
}

variable "autoscaling_target_cpu" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "autoscaling_target_memory" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 80
}

variable "enable_monitoring" {
  description = "Whether to enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "keycloak_external_url" {
  description = "External Keycloak URL accessible from browsers"
  type        = string
  default     = ""
}

variable "keycloak_realm" {
  description = "Keycloak realm name"
  type        = string
  default     = "mcp-gateway"
}

variable "keycloak_client_id" {
  description = "Keycloak client ID for web application"
  type        = string
  default     = "mcp-gateway-web"
}

variable "keycloak_client_secret" {
  description = "Keycloak client secret for web application"
  type        = string
  default     = ""
  sensitive   = true
}

variable "keycloak_m2m_client_id" {
  description = "Keycloak machine-to-machine client ID"
  type        = string
  default     = "mcp-gateway-m2m"
}

variable "keycloak_m2m_client_secret" {
  description = "Keycloak machine-to-machine client secret"
  type        = string
  default     = ""
  sensitive   = true
}

# EFS Configuration
variable "efs_throughput_mode" {
  description = "Throughput mode for EFS (bursting or provisioned)"
  type        = string
  default     = "provisioned"
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s for EFS (only used if throughput_mode is provisioned)"
  type        = number
  default     = 100
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}


# Domain Configuration (Optional)
variable "domain_name" {
  description = "Domain name for the MCP Gateway Registry (optional)"
  type        = string
  default     = ""
}

variable "create_route53_record" {
  description = "Whether to create Route53 DNS record for the domain"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (required if create_route53_record is true)"
  type        = string
  default     = ""
}