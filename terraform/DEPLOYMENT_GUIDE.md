# MCP Gateway Registry - Complete Deployment Guide

This guide covers all deployment options for MCP Gateway Registry, from local development to production AWS ECS.

## 📋 Deployment Options Overview

| Option | Use Case | Complexity | Cost | Setup Time |
|--------|----------|------------|------|------------|
| **Docker Compose** | Local development, testing | Low | Free | 5 minutes |
| **AWS EC2** | Small production, staging | Medium | ~$50/month | 30 minutes |
| **AWS ECS Fargate** | Enterprise production | Medium | ~$200-300/month | 20 minutes |

---

## 🖥️ Option 1: Local Development (Docker Compose)

**Best for:** Development, testing, demos

### Quick Start
```bash
git clone https://github.com/agentic-community/mcp-gateway-registry.git
cd mcp-gateway-registry
cp .env.example .env
# Edit .env with your settings
./build_and_run.sh --prebuilt
```

### Access
- Registry: http://localhost:7860
- Auth Server: http://localhost:8888
- Keycloak: http://localhost:8080

### Documentation
- [Complete Setup Guide](../docs/complete-setup-guide.md)
- [Quick Start](../docs/quick-start.md)

---

## ☁️ Option 2: AWS EC2 Single Instance

**Best for:** Small production deployments, staging environments

### Prerequisites
- AWS Account
- EC2 instance (t3.large or larger)
- Domain name (optional, for HTTPS)

### Setup Steps
1. Launch EC2 instance (Ubuntu 22.04)
2. Install Docker and Docker Compose
3. Clone repository
4. Configure environment
5. Run deployment script

### Detailed Guide
See [Installation Guide](../docs/installation.md) for complete EC2 setup instructions.

### Estimated Cost
- EC2 t3.large: ~$60/month
- EBS storage: ~$10/month
- Data transfer: ~$10/month
- **Total: ~$80/month**

---

## 🚀 Option 3: AWS ECS Fargate (Production)

**Best for:** Enterprise production deployments requiring high availability

### What You Get
- **Multi-AZ deployment** across 3 availability zones
- **Auto-scaling** (2-4 tasks per service)
- **Load balancing** with Application Load Balancer
- **Managed database** (Aurora PostgreSQL Serverless v2)
- **Monitoring** (11 CloudWatch alarms)
- **HTTPS** support with ACM certificates
- **High availability** (no single points of failure)

### Prerequisites
- AWS Account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured
- (Optional) ACM certificate for HTTPS

### Quick Start

#### Step 1: Navigate to Terraform Directory
```bash
cd terraform/aws-ecs/
```

#### Step 2: Configure Deployment
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
name       = "mcp-gateway"
aws_region = "us-east-1"
vpc_cidr   = "10.0.0.0/16"

# Optional: Enable HTTPS
# certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"

# Optional: Enable monitoring
enable_monitoring = true
alarm_email       = "ops@example.com"
```

#### Step 3: Initialize Terraform
```bash
terraform init
```

#### Step 4: Review Plan
```bash
terraform plan
```

#### Step 5: Deploy
```bash
terraform apply
```

#### Step 6: Get Access URL
```bash
# Get ALB DNS name
terraform output mcp_gateway_alb_dns

# Access registry
open http://$(terraform output -raw mcp_gateway_alb_dns)
```

### What Gets Created

**Network Infrastructure:**
- 1 VPC with 3 availability zones
- 3 Public subnets
- 3 Private subnets
- 3 NAT gateways (one per AZ)
- 1 Internet gateway
- VPC endpoints (S3, STS)

**Compute Resources:**
- 1 ECS Cluster
- 3 ECS Services (Registry, Auth, Keycloak)
- 6-12 ECS Tasks (auto-scaled)
- 1 Application Load Balancer
- 3 Target groups

**Database:**
- 1 Aurora PostgreSQL Cluster (Serverless v2)
- 2 Aurora instances (Multi-AZ)

**Monitoring:**
- 11 CloudWatch alarms
- 1 SNS topic for notifications
- CloudWatch log groups

### Estimated Cost

| Component | Monthly Cost |
|-----------|-------------|
| NAT Gateways (3) | $97 |
| ECS Fargate | $50-150 |
| Aurora PostgreSQL | $30-60 |
| Application Load Balancer | $16 |
| CloudWatch | $5 |
| **Total** | **$198-328/month** |

### Detailed Documentation
See [AWS ECS README](aws-ecs/README.md) for complete deployment guide.

---

## 🔄 Migration Path

### From Local to EC2
1. Export Docker images
2. Push to container registry
3. Deploy on EC2 with same docker-compose.yml
4. Update DNS/environment variables

### From EC2 to ECS
1. Ensure application works on EC2
2. Configure Terraform with same environment variables
3. Deploy to ECS
4. Test thoroughly
5. Update DNS to point to ALB
6. Decommission EC2

### From ECS to ECS (Updates)
```bash
cd terraform/aws-ecs/
git pull
terraform plan
terraform apply
```

---

## 🎯 Choosing the Right Deployment

### Use Docker Compose if:
- ✅ You're developing or testing
- ✅ You need quick setup
- ✅ You're running on a laptop/desktop
- ✅ Cost is a primary concern
- ❌ You don't need high availability
- ❌ You don't need auto-scaling

### Use AWS EC2 if:
- ✅ You need a simple production setup
- ✅ You have moderate traffic
- ✅ You want to minimize costs
- ✅ You're comfortable with manual scaling
- ❌ You don't need multi-AZ redundancy
- ❌ You don't need auto-scaling

### Use AWS ECS if:
- ✅ You need enterprise-grade production
- ✅ You require high availability
- ✅ You need auto-scaling
- ✅ You want infrastructure-as-code
- ✅ You need multi-AZ redundancy
- ✅ You want managed infrastructure
- ✅ You need monitoring and alerting

---

## 📊 Feature Comparison

| Feature | Docker Compose | AWS EC2 | AWS ECS |
|---------|---------------|---------|---------|
| **Setup Time** | 5 minutes | 30 minutes | 20 minutes |
| **High Availability** | ❌ | ❌ | ✅ |
| **Auto-scaling** | ❌ | ❌ | ✅ |
| **Multi-AZ** | ❌ | ❌ | ✅ |
| **Monitoring** | Basic | Manual | ✅ CloudWatch |
| **HTTPS** | Manual | Manual | ✅ ACM |
| **Database** | SQLite | PostgreSQL | ✅ Aurora |
| **Cost** | Free | ~$80/mo | ~$200-300/mo |
| **Maintenance** | Manual | Manual | Managed |
| **Infrastructure-as-Code** | ❌ | ❌ | ✅ Terraform |

---

## 🔧 Post-Deployment

### Configure Keycloak
```bash
# For all deployments
cd keycloak/setup/
./init-keycloak.sh
```

### Create First Agent
```bash
cd keycloak/setup/
./setup-agent-service-account.sh --agent-id my-agent --group mcp-servers-unrestricted
```

### Test Deployment
```bash
# Test MCP connectivity
cd tests/
./mcp_cmds.sh ping

# Test with Python client
cd cli/
uv run python mcp_client.py --operation ping
```

---

## 📚 Additional Resources

- [Complete Setup Guide](../docs/complete-setup-guide.md)
- [Authentication Guide](../docs/auth.md)
- [Keycloak Integration](../docs/keycloak-integration.md)
- [Observability Guide](../docs/OBSERVABILITY.md)
- [Troubleshooting](../docs/FAQ.md)

---

## 🆘 Getting Help

- [GitHub Issues](https://github.com/agentic-community/mcp-gateway-registry/issues)
- [GitHub Discussions](https://github.com/agentic-community/mcp-gateway-registry/discussions)
- [Documentation](../docs/)
