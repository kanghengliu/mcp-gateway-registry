# MCP Gateway Registry - AWS ECS Deployment

Production-ready deployment of MCP Gateway Registry on AWS ECS Fargate with auto-scaling, monitoring, and multi-AZ high availability.

## 🎯 What This Deploys

This Terraform configuration creates a complete production infrastructure:

### **Infrastructure Components**
- **VPC**: Multi-AZ network with 3 availability zones
- **NAT Gateways**: 3 gateways (one per AZ) for high availability
- **ECS Cluster**: Fargate-based container orchestration
- **Application Load Balancer**: HTTP/HTTPS traffic distribution
- **Aurora PostgreSQL**: Serverless v2 database (0.5-2.0 ACU)
- **Security Groups**: Least-privilege network access
- **VPC Endpoints**: Private AWS API access (S3, STS)

### **MCP Gateway Services**
- **Registry Service**: Web UI and REST API (port 7860)
- **Auth Server**: Authentication and authorization (port 8888)
- **Keycloak**: Identity provider (port 8080)

### **Production Features**
- ✅ **Auto-scaling**: 2-4 tasks based on CPU (70%) and memory (80%)
- ✅ **Multi-AZ**: Services distributed across 3 availability zones
- ✅ **Monitoring**: 11 CloudWatch alarms with email notifications
- ✅ **HTTPS**: Optional ACM certificate integration
- ✅ **High Availability**: No single points of failure

## 📋 Prerequisites

### **Required**
- AWS Account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured with credentials

### **Optional**
- ACM certificate for HTTPS (recommended for production)
- Email address for CloudWatch alarm notifications

## 🚀 Quick Start

### **Step 1: Configure**
```bash
cd terraform/aws-ecs/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
```

### **Step 2: Initialize**
```bash
terraform init
```

### **Step 3: Plan**
```bash
terraform plan
```

### **Step 4: Deploy**
```bash
terraform apply
```

### **Step 5: Access**
```bash
# Get the ALB DNS name
terraform output mcp_gateway_alb_dns

# Access the registry
open http://$(terraform output -raw mcp_gateway_alb_dns)
```

## ⚙️ Configuration Options

### **Basic Configuration**
```hcl
# terraform.tfvars
name       = "mcp-gateway"      # Deployment name
aws_region = "us-east-1"        # AWS region
vpc_cidr   = "10.0.0.0/16"      # VPC CIDR block
```

### **HTTPS Configuration**
```hcl
# Provide ACM certificate ARN to enable HTTPS
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"
```

### **Monitoring Configuration**
```hcl
enable_monitoring = true
alarm_email       = "ops@example.com"  # Receives CloudWatch alarms
```

## 📊 What Gets Created

### **Network Resources**
- 1 VPC
- 3 Public Subnets (one per AZ)
- 3 Private Subnets (one per AZ)
- 3 NAT Gateways (one per AZ)
- 1 Internet Gateway
- Route Tables and Routes
- VPC Endpoints (S3, STS)

### **Compute Resources**
- 1 ECS Cluster
- 3 ECS Services (Registry, Auth, Keycloak)
- 6-12 ECS Tasks (2-4 per service with auto-scaling)
- 1 Application Load Balancer
- 3 Target Groups

### **Database Resources**
- 1 Aurora PostgreSQL Cluster (Serverless v2)
- 2 Aurora Instances (Multi-AZ)

### **Monitoring Resources**
- 11 CloudWatch Alarms
- 1 SNS Topic (for alarm notifications)
- CloudWatch Log Groups

## 💰 Cost Estimate

| Component | Monthly Cost (USD) |
|-----------|-------------------|
| NAT Gateways (3) | $97 |
| ECS Fargate | $50-150 (auto-scaled) |
| Aurora PostgreSQL | $30-60 (serverless) |
| Application Load Balancer | $16 |
| CloudWatch | $5 |
| **Total** | **$198-328/month** |

**Note:** Costs vary based on:
- Auto-scaling (task count)
- Database usage (ACU hours)
- Data transfer
- CloudWatch metrics/logs

## 🔧 Advanced Configuration

### **Build Local Images into Private ECR**
If you can't publish to Docker Hub, Terraform can now build the registry and auth images locally and push them to a private ECR repository:

```hcl
# terraform.tfvars
use_private_ecr     = true
local_image_tag     = "dev"
local_image_force_rebuild = "git-sha-2025-11-12" # bump to force a rebuild
```

What happens:
- Terraform creates two ECR repositories (`<name>-registry` and `<name>-auth`).
- During `terraform apply`, `docker build` runs from your local repo root for `docker/Dockerfile.registry` and `docker/Dockerfile.auth`.
- Images are tagged as `<account-id>.dkr.ecr.<region>.amazonaws.com/<name>-registry:<local_image_tag>` (same for auth) and pushed.
- ECS services are automatically pointed at those private images.

Requirements:
- Docker CLI and AWS CLI installed on the machine running Terraform.
- IAM permissions to create/read ECR repositories and to push images.

You can still override image URIs manually with `registry_image_override` or `auth_server_image_override` when `use_private_ecr = false`.

### **Custom Docker Images**
To use custom-built images instead of pre-built ones:

```hcl
# In modules/mcp-gateway/ecs-services.tf
# Update image URIs to point to your registry
```

### **Scaling Configuration**
Adjust auto-scaling parameters in `main.tf`:

```hcl
module "mcp_gateway" {
  # ...
  autoscaling_min_capacity  = 2   # Minimum tasks
  autoscaling_max_capacity  = 10  # Maximum tasks
  autoscaling_target_cpu    = 70  # CPU target %
  autoscaling_target_memory = 80  # Memory target %
}
```

### **Database Configuration**
Adjust Aurora capacity in `modules/mcp-gateway/database.tf`:

```hcl
serverlessv2_scaling_configuration {
  min_capacity = 0.5  # Minimum ACU
  max_capacity = 4.0  # Maximum ACU
}
```

## 📈 Monitoring

### **CloudWatch Alarms**
11 alarms monitor critical metrics:

**ECS Services (6 alarms):**
- Registry CPU > 85%
- Registry Memory > 85%
- Auth CPU > 85%
- Auth Memory > 85%
- Keycloak CPU > 85%
- Keycloak Memory > 85%

**Load Balancer (3 alarms):**
- Unhealthy targets > 0
- 5xx errors > 10/5min
- Response time > 1s

**Database (2 alarms):**
- RDS CPU > 80%
- RDS connections > 80

### **Accessing Logs**
```bash
# View ECS service logs
aws logs tail /aws/ecs/mcp-gateway --follow

# View specific service
aws logs tail /aws/ecs/mcp-gateway/registry --follow
```

## 🔒 Security

### **Network Security**
- All services in private subnets
- ALB in public subnets (only entry point)
- Security groups with least-privilege rules
- VPC endpoints for AWS API calls (no internet)

### **Access Control**
- IAM roles for ECS tasks
- Secrets Manager for sensitive data
- Keycloak for user authentication
- Fine-grained authorization via scopes

## 🔄 Updates and Maintenance

### **Update Infrastructure**
```bash
# Pull latest changes
git pull

# Review changes
terraform plan

# Apply updates
terraform apply
```

### **Update Application**
```bash
# ECS will automatically pull new images on task restart
# Force new deployment
aws ecs update-service \
  --cluster mcp-gateway-ecs-cluster \
  --service mcp-gateway-registry \
  --force-new-deployment
```

## 🗑️ Cleanup

### **Destroy Infrastructure**
```bash
terraform destroy
```

**Warning:** This will delete:
- All ECS services and tasks
- Aurora database (with final snapshot)
- VPC and networking
- CloudWatch alarms
- All data (unless backed up)

## 📚 Additional Resources

- [MCP Gateway Documentation](../../docs/)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🆘 Troubleshooting

### **Services Not Starting**
```bash
# Check ECS service events
aws ecs describe-services \
  --cluster mcp-gateway-ecs-cluster \
  --services mcp-gateway-registry

# Check task logs
aws logs tail /aws/ecs/mcp-gateway/registry --follow
```

### **Database Connection Issues**
```bash
# Verify security group rules
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=mcp-gateway*"

# Check Aurora cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier mcp-gateway-postgres
```

### **ALB Health Checks Failing**
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>
```

## 📞 Support

For issues and questions:
- [GitHub Issues](https://github.com/agentic-community/mcp-gateway-registry/issues)
- [Documentation](../../docs/)
- [Community Discussions](https://github.com/agentic-community/mcp-gateway-registry/discussions)
