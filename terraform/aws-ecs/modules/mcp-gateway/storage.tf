# EFS storage resources for MCP Gateway Registry

# EFS file system for persistent storage
resource "aws_efs_file_system" "mcp_efs" {
  creation_token   = "${local.name_prefix}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = var.efs_throughput_mode

  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null

  encrypted = true
  tags      = local.common_tags
}

# EFS mount targets
resource "aws_efs_mount_target" "mcp_efs_mount" {
  count          = length(var.private_subnet_ids)
  file_system_id = aws_efs_file_system.mcp_efs.id
  subnet_id      = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${local.name_prefix}-efs-"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix} EFS Security Group"
  })
}

# EFS Access Points
resource "aws_efs_access_point" "servers" {
  file_system_id = aws_efs_file_system.mcp_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/servers"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix} Servers"
  })
}

resource "aws_efs_access_point" "models" {
  file_system_id = aws_efs_file_system.mcp_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/models"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix} Models"
  })
}

resource "aws_efs_access_point" "logs" {
  file_system_id = aws_efs_file_system.mcp_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/logs"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix} Logs"
  })
}