# EFS storage resources for MCP Gateway Registry

module "efs" {
  source  = "terraform-aws-modules/efs/aws"
  version = "~> 2.0"

  # File system configuration
  name             = "${local.name_prefix}-efs"
  creation_token   = "${local.name_prefix}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = var.efs_throughput_mode

  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null

  encrypted = true

  # Mount targets - one per private subnet
  mount_targets = {
    for idx, subnet_id in var.private_subnet_ids : "mount-${idx}" => {
      subnet_id = subnet_id
    }
  }

  # Security group configuration
  create_security_group      = true
  security_group_vpc_id      = var.vpc_id
  security_group_name        = "${local.name_prefix}-efs-"
  security_group_use_name_prefix = true

  security_group_ingress_rules = {
    nfs = {
      description = "NFS from VPC"
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = data.aws_vpc.vpc.cidr_block
    }
  }

  security_group_egress_rules = {
    all = {
      description = "Allow all outbound"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # Access points
  access_points = {
    servers = {
      name = "${local.name_prefix}-servers"
      posix_user = {
        gid = 1000
        uid = 1000
      }
      root_directory = {
        path = "/servers"
        creation_info = {
          owner_gid   = 1000
          owner_uid   = 1000
          permissions = "755"
        }
      }
      tags = merge(local.common_tags, {
        Name = "${local.name_prefix} Servers"
      })
    }

    models = {
      name = "${local.name_prefix}-models"
      posix_user = {
        gid = 1000
        uid = 1000
      }
      root_directory = {
        path = "/models"
        creation_info = {
          owner_gid   = 1000
          owner_uid   = 1000
          permissions = "755"
        }
      }
      tags = merge(local.common_tags, {
        Name = "${local.name_prefix} Models"
      })
    }

    logs = {
      name = "${local.name_prefix}-logs"
      posix_user = {
        gid = 1000
        uid = 1000
      }
      root_directory = {
        path = "/logs"
        creation_info = {
          owner_gid   = 1000
          owner_uid   = 1000
          permissions = "755"
        }
      }
      tags = merge(local.common_tags, {
        Name = "${local.name_prefix} Logs"
      })
    }
  }

  tags = local.common_tags
}
