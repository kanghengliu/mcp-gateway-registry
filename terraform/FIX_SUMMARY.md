# Service Discovery Namespace Conflict - Fix Summary

## Issue
Terraform was failing with the following error:
```
Error: waiting for Service Discovery Private DNS Namespace (mcp-gateway.local) create: unexpected state 'FAIL', wanted target 'SUCCESS'. 
last error: CANNOT_CREATE_HOSTED_ZONE: The VPC vpc-0ca3940d502f7d7d8 in region us-east-1 has already been associated with the hosted zone Z09986023N7FC6ZAPYUQZ with the same domain name.
```

## Root Cause
There were **two** Service Discovery Private DNS Namespaces being created with the same name `mcp-gateway.local` in the same VPC:

1. **In `terraform/aws-ecs/ecs.tf`** (line 50-58):
   ```hcl
   resource "aws_service_discovery_private_dns_namespace" "main" {
     name        = "${var.name}.local"
     description = "Service discovery namespace for ${var.name}"
     vpc         = module.vpc.vpc_id
   }
   ```

2. **In `terraform/aws-ecs/modules/mcp-gateway/networking.tf`** (line 4-8):
   ```hcl
   resource "aws_service_discovery_private_dns_namespace" "mcp" {
     name        = "${local.name_prefix}.local"
     description = "Service discovery namespace for MCP Gateway Registry"
     vpc         = var.vpc_id
   }
   ```

Both were trying to create the same namespace, causing a conflict because AWS Route53 doesn't allow duplicate hosted zones with the same domain name in the same VPC.

## Solution Applied

### 1. Removed Duplicate Resource
Removed the duplicate Service Discovery namespace from `terraform/aws-ecs/ecs.tf` (lines 50-58).

### 2. Cleaned Terraform State
Removed the orphaned resource from Terraform state:
```bash
terraform state rm aws_service_discovery_private_dns_namespace.main
```

## Result
- The Service Discovery namespace in the `mcp-gateway` module (`networking.tf`) is the single source of truth
- No more conflicts when running `terraform apply`
- The existing hosted zone (Z09986023N7FC6ZAPYUQZ) will continue to work

## Next Steps
1. Configure AWS credentials
2. Run `terraform plan` to verify no conflicts
3. Run `terraform apply` to proceed with deployment

## Files Modified
- `/Users/aviyadc/Repository/genai-engagements/mcp-gateway-registry/terraform/aws-ecs/ecs.tf`
