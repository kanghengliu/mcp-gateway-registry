variable "name" {
  description = "Name of the deployment"
  type        = string
  default     = "mcp-gateway"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional, creates HTTP-only if not provided)"
  type        = string
  default     = ""
}

variable "use_private_ecr" {
  description = "Set to true to build registry/auth images locally and push them to a private ECR repository automatically"
  type        = bool
  default     = true
}

variable "local_image_tag" {
  description = "Docker image tag to use when pushing locally-built images to ECR"
  type        = string
  default     = "local"
}

variable "registry_image_override" {
  description = "Optional fully-qualified image URI to use for the registry service (overrides defaults when use_private_ecr = false)"
  type        = string
  default     = ""
}

variable "auth_server_image_override" {
  description = "Optional fully-qualified image URI to use for the auth service (overrides defaults when use_private_ecr = false)"
  type        = string
  default     = ""
}

variable "local_image_force_rebuild" {
  description = "Change this value (e.g., set to current git commit) to force Terraform to rebuild and push local images"
  type        = string
  default     = ""
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

variable "alb_scheme" {
  description = "Scheme for the application load balancer (internal or internet-facing)"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["internal", "internet-facing"], var.alb_scheme)
    error_message = "alb_scheme must be either \"internal\" or \"internet-facing\"."
  }
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks allowed to reach the public ALB listeners"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
