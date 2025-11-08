# MCP Gateway Registry Terraform Module

This Terraform module deploys the MCP Gateway Registry to AWS ECS Fargate with Aurora Serverless PostgreSQL and Keycloak authentication.

## Features

- **ECS Fargate**: Serverless container deployment
- **Aurora Serverless v2**: PostgreSQL database with auto-scaling
- **EFS**: Shared storage for MCP servers, models, and logs
- **Application Load Balancer**: With multiple listeners for different services
- **Service Connect**: For inter-service communication
- **Keycloak Authentication**: Integrated identity and access management
- **Secrets Manager**: Secure credential management
- **CloudWatch Logs**: Centralized logging

## Architecture

The module deploys two main services:

1. **Registry Service** - Main MCP Gateway Registry with Gradio UI (ports 80, 443, 7860)
2. **Auth Service** - Authentication service integrated with Keycloak (port 8888)

## Usage

### Basic Usage (with pre-built images)

```hcl
module "mcp_gateway" {
  source = "./modules/mcp-gateway"

  # Required: Basic configuration
  name = "mcp-gateway-prod"

  # Required: Network configuration
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-12345678", "subnet-87654321"]
  public_subnet_ids  = ["subnet-abcdef12", "subnet-21fedcba"]

  # Required: ECS configuration
  ecs_cluster_arn         = "arn:aws:ecs:us-west-2:123456789012:cluster/my-cluster"
  ecs_cluster_name        = "my-cluster"
  task_execution_role_arn = "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"

  # Optional: Keycloak configuration
  keycloak_ingress_cidr = "10.0.0.0/16"  # VPC CIDR for internal access

  # That's it! Module uses pre-built images from mcpgateway Docker Hub by default
}
```

### Advanced Usage (with custom configuration)

```hcl
module "mcp_gateway" {
  source = "./modules/mcp-gateway"

  # Required configuration
  name                    = "mcp-gateway-prod"
  vpc_id                  = "vpc-12345678"
  private_subnet_ids      = ["subnet-12345678", "subnet-87654321"]
  public_subnet_ids       = ["subnet-abcdef12", "subnet-21fedcba"]
  ecs_cluster_arn         = "arn:aws:ecs:us-west-2:123456789012:cluster/my-cluster"
  ecs_cluster_name        = "my-cluster"
  task_execution_role_arn = "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"

  # Optional: Custom container images (override pre-built images)
  # registry_image_uri    = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-registry:latest"
  # auth_server_image_uri = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-auth:latest"
  # keycloak_image_uri    = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-keycloak:latest"

  # Optional: Domain configuration
  domain_name           = "mcp.example.com"
  create_route53_record = true
  route53_zone_id       = "Z1D633PJN98FT9"

  # Optional: Resource configuration
  cpu               = "2048"
  memory            = "4096"
  registry_replicas = 2
  auth_replicas     = 2
  keycloak_replicas = 2

  # Optional: Database configuration
  keycloak_postgres_min_capacity = 0.5
  keycloak_postgres_max_capacity = 4.0

  # Optional: Networking
  alb_scheme            = "internet-facing"
  ingress_cidr_blocks   = ["0.0.0.0/0"]
  keycloak_ingress_cidr = "10.0.0.0/16"

  # Optional: Keycloak client secrets (if pre-configured)
  keycloak_client_secret     = "your-client-secret"
  keycloak_m2m_client_secret = "your-m2m-client-secret"

  # Optional: Tags
  additional_tags = {
    Environment = "production"
    Owner       = "platform-team"
    CostCenter  = "engineering"
  }
}
```

## Prerequisites

1. **Existing Infrastructure**: This module requires existing VPC, ECS cluster, and task execution role
2. **Container Images**: Module now uses pre-built images from Docker Hub (mcpgateway organization) by default - no build required!
3. **Keycloak Setup**: Keycloak is automatically deployed as part of this module with Aurora PostgreSQL backend

## Container Images

This module uses **pre-built images** from Docker Hub by default:

- `mcpgateway/registry:latest` - Main MCP Gateway Registry service
- `mcpgateway/auth-server:latest` - Authentication service
- `mcpgateway/keycloak:latest` - Keycloak identity provider

These images are automatically pulled from Docker Hub and match the official deployment from:
https://github.com/agentic-community/mcp-gateway-registry

**No build step required!** Simply deploy the module and it will use the latest pre-built images.

If you need to use custom images (e.g., from ECR), you can override the default image URIs:

```hcl
module "mcp_gateway" {
  source = "./modules/mcp-gateway"

  # Override with custom images
  registry_image_uri    = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-registry:latest"
  auth_server_image_uri = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-auth:latest"

  # ... other configuration
}
```

## Keycloak Configuration

**Keycloak is automatically deployed** as part of this module with the following setup:

- **Database**: Aurora Serverless PostgreSQL (auto-scaling, separate from application data)
- **Default Realm**: `mcp-gateway`
- **Default Clients**: `mcp-gateway-web` (web UI) and `mcp-gateway-m2m` (machine-to-machine)
- **Internal Access**: Via dedicated internal ALB for service-to-service communication
- **Admin Credentials**: Stored securely in AWS Secrets Manager

After deployment, you can access Keycloak admin console using the credentials from Secrets Manager to:

1. Configure additional realms and clients
2. Set up identity providers (LDAP, SAML, Social logins)
3. Customize authentication flows
4. Manage users and groups

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix for MCP Gateway Registry resources | `string` | n/a | yes |
| vpc_id | ID of the VPC where resources will be created | `string` | n/a | yes |
| private_subnet_ids | List of private subnet IDs for ECS services | `list(string)` | n/a | yes |
| public_subnet_ids | List of public subnet IDs for ALB | `list(string)` | n/a | yes |
| ecs_cluster_arn | ARN of the existing ECS cluster | `string` | n/a | yes |
| ecs_cluster_name | Name of the existing ECS cluster | `string` | n/a | yes |
| task_execution_role_arn | ARN of the task execution IAM role | `string` | n/a | yes |
| registry_image_uri | Container image URI for registry service | `string` | `"mcpgateway/registry:latest"` | no |
| auth_server_image_uri | Container image URI for auth server service | `string` | `"mcpgateway/auth-server:latest"` | no |
| keycloak_image_uri | Container image URI for Keycloak service | `string` | `"mcpgateway/keycloak:latest"` | no |
| cpu | CPU allocation for containers | `string` | `"1024"` | no |
| memory | Memory allocation for containers | `string` | `"2048"` | no |
| registry_replicas | Number of replicas for registry service | `number` | `1` | no |
| auth_replicas | Number of replicas for auth service | `number` | `1` | no |
| keycloak_url | Keycloak server URL | `string` | `"http://keycloak:8080"` | no |
| keycloak_external_url | External Keycloak URL | `string` | `""` | no |
| keycloak_realm | Keycloak realm name | `string` | `"mcp-gateway"` | no |
| keycloak_client_id | Keycloak client ID for web application | `string` | `"mcp-gateway-web"` | no |
| keycloak_client_secret | Keycloak client secret for web application | `string` | `""` | no |
| keycloak_m2m_client_id | Keycloak machine-to-machine client ID | `string` | `"mcp-gateway-m2m"` | no |
| keycloak_m2m_client_secret | Keycloak machine-to-machine client secret | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| database_endpoint | PostgreSQL cluster endpoint |
| alb_dns_name | DNS name of the Application Load Balancer |
| service_urls | URLs for accessing the MCP Gateway Registry services |
| efs_id | EFS file system ID |
| secret_arns | ARNs of secrets stored in AWS Secrets Manager |
| admin_credentials | Admin credentials for initial setup |

## Security Considerations

- All secrets are stored in AWS Secrets Manager
- EFS storage is encrypted at rest and in transit
- PostgreSQL database is encrypted
- Security groups follow least privilege principles
- Container logs are sent to CloudWatch
- IAM roles use minimal required permissions

## Cost Optimization

- Aurora Serverless v2 automatically scales based on demand
- EFS uses provisioned throughput mode (configurable)
- ECS Fargate with FARGATE capacity provider
- CloudWatch logs with 30-day retention

## Monitoring and Logging

- CloudWatch Logs for all container output
- ECS Container Insights enabled
- Health checks configured for all services
- Performance Insights enabled for Aurora

## License

This module is provided as-is for demonstration purposes.