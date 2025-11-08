# ECS Services for MCP Gateway Registry (Keycloak Auth Only)

# ECS Service: Auth Server
module "ecs_service_auth" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name         = "${local.name_prefix}-auth"
  cluster_arn  = var.ecs_cluster_arn
  cpu          = tonumber(var.cpu)
  memory       = tonumber(var.memory)
  desired_count = var.enable_autoscaling ? var.autoscaling_min_capacity : var.auth_replicas
  enable_autoscaling = var.enable_autoscaling
  autoscaling_min_capacity = var.autoscaling_min_capacity
  autoscaling_max_capacity = var.autoscaling_max_capacity
  autoscaling_policies = var.enable_autoscaling ? {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value = var.autoscaling_target_cpu
      }
    }
    memory = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageMemoryUtilization"
        }
        target_value = var.autoscaling_target_memory
      }
    }
  } : {}

  requires_compatibilities = ["FARGATE"]
  capacity_provider_strategy = {
    FARGATE = {
      capacity_provider = "FARGATE"
      weight = 100
      base   = 1
    }
  }

  # Task roles
  create_task_exec_iam_role = true
  task_exec_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }
  create_tasks_iam_role  = true
  tasks_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }

  # Enable Service Connect
  service_connect_configuration = {
    namespace = aws_service_discovery_private_dns_namespace.mcp.arn
    service = [{
      client_alias = {
        port     = 8888
        dns_name = "auth-server"
      }
      port_name      = "auth-server"
      discovery_name = "auth-server"
    }]
  }

  # Container definitions
  container_definitions = {
    auth-server = {
      cpu                    = tonumber(var.cpu)
      memory                 = tonumber(var.memory)
      essential              = true
      image                  = var.auth_server_image_uri
      readonlyRootFilesystem = false

      portMappings = [
        {
          name           = "auth-server"
          containerPort = 8888
          protocol       = "tcp"
        }
      ]

      environment = [
        {
          name  = "REGISTRY_URL"
          value = "http://registry:7860"
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.id
        },
        {
          name  = "AUTH_PROVIDER"
          value = "keycloak"
        },
        {
          name  = "KEYCLOAK_ENABLED"
          value = "true"
        },
        {
          name  = "KEYCLOAK_URL"
          value = "http://${module.keycloak_alb.dns_name}:8080"
        },
        {
          name  = "KEYCLOAK_EXTERNAL_URL"
          value = var.keycloak_external_url != "" ? var.keycloak_external_url : "http://${module.keycloak_alb.dns_name}:8080"
        },
        {
          name  = "KEYCLOAK_REALM"
          value = var.keycloak_realm
        },
        {
          name  = "KEYCLOAK_CLIENT_ID"
          value = var.keycloak_client_id
        },
        {
          name  = "KEYCLOAK_M2M_CLIENT_ID"
          value = var.keycloak_m2m_client_id
        }
      ]

      secrets = concat([
        {
          name      = "SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.secret_key.arn
        }
      ],
      var.keycloak_client_secret != "" ? [{
        name      = "KEYCLOAK_CLIENT_SECRET"
        valueFrom = aws_secretsmanager_secret.keycloak_client_secret[0].arn
      }] : [],
      var.keycloak_m2m_client_secret != "" ? [{
        name      = "KEYCLOAK_M2M_CLIENT_SECRET"
        valueFrom = aws_secretsmanager_secret.keycloak_m2m_client_secret[0].arn
      }] : [])

      mountPoints = [
        {
          sourceVolume  = "mcp-logs"
          containerPath = "/app/logs"
          readOnly      = false
        }
      ]

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_name             = "/ecs/${local.name_prefix}-auth-server"
      cloudwatch_log_group_retention_in_days = 30

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8888/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  }

  volume = {
    mcp-logs = {
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.mcp_efs.id
        access_point_id    = aws_efs_access_point.logs.id
        transit_encryption = "ENABLED"
      }
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["auth"].arn
      container_name   = "auth-server"
      container_port   = 8888
    }
  }

  subnet_ids = var.private_subnet_ids
  security_group_ingress_rules = {
    alb_8888 = {
      description                  = "Auth server port"
      from_port                    = 8888
      to_port                      = 8888
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb.security_group_id
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = local.common_tags

  depends_on = [module.keycloak_alb]
}

# ECS Service: Registry (Main service with nginx, SSL, FAISS, models)
module "ecs_service_registry" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name         = "${local.name_prefix}-registry"
  cluster_arn  = var.ecs_cluster_arn
  cpu          = tonumber(var.cpu)
  memory       = tonumber(var.memory)
  desired_count = var.enable_autoscaling ? var.autoscaling_min_capacity : var.registry_replicas
  enable_autoscaling = var.enable_autoscaling
  autoscaling_min_capacity = var.autoscaling_min_capacity
  autoscaling_max_capacity = var.autoscaling_max_capacity
  autoscaling_policies = var.enable_autoscaling ? {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value = var.autoscaling_target_cpu
      }
    }
    memory = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageMemoryUtilization"
        }
        target_value = var.autoscaling_target_memory
      }
    }
  } : {}

  requires_compatibilities = ["FARGATE"]
  capacity_provider_strategy = {
    FARGATE = {
      capacity_provider = "FARGATE"
      weight = 100
      base   = 1
    }
  }

  # Task roles
  create_task_exec_iam_role = true
  task_exec_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }
  create_tasks_iam_role  = true
  tasks_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }

  # Enable Service Connect
  service_connect_configuration = {
    namespace = aws_service_discovery_private_dns_namespace.mcp.arn
    service = [{
      client_alias = {
        port     = 7860
        dns_name = "registry"
      }
      port_name      = "registry"
      discovery_name = "registry"
    }]
  }

  # Container definitions
  container_definitions = {
    registry = {
      cpu                    = tonumber(var.cpu)
      memory                 = tonumber(var.memory)
      essential              = true
      image                  = var.registry_image_uri
      readonlyRootFilesystem = false

      portMappings = [
        {
          name           = "http"
          containerPort = 80
          protocol       = "tcp"
        },
        {
          name           = "https"
          containerPort = 443
          protocol       = "tcp"
        },
        {
          name           = "registry"
          containerPort = 7860
          protocol       = "tcp"
        }
      ]

      environment = [
        {
          name  = "EC2_PUBLIC_DNS"
          value = var.domain_name != "" ? var.domain_name : module.alb.dns_name
        },
        {
          name  = "AUTH_SERVER_URL"
          value = "http://auth-server:8888"
        },
        {
          name  = "AUTH_SERVER_EXTERNAL_URL"
          value = var.domain_name != "" ? "https://${var.domain_name}:8888" : "http://${module.alb.dns_name}:8888"
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.id
        },
        {
          name  = "AUTH_PROVIDER"
          value = "keycloak"
        },
        {
          name  = "KEYCLOAK_ENABLED"
          value = "true"
        },
        {
          name  = "KEYCLOAK_URL"
          value = "http://${module.keycloak_alb.dns_name}:8080"
        },
        {
          name  = "KEYCLOAK_EXTERNAL_URL"
          value = var.keycloak_external_url != "" ? var.keycloak_external_url : "http://${module.keycloak_alb.dns_name}:8080"
        },
        {
          name  = "KEYCLOAK_REALM"
          value = var.keycloak_realm
        },
        {
          name  = "KEYCLOAK_CLIENT_ID"
          value = var.keycloak_client_id
        }
      ]

      secrets = concat([
        {
          name      = "SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.secret_key.arn
        },
        {
          name      = "ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.admin_password.arn
        }
      ],
      var.keycloak_client_secret != "" ? [{
        name      = "KEYCLOAK_CLIENT_SECRET"
        valueFrom = aws_secretsmanager_secret.keycloak_client_secret[0].arn
      }] : [])

      mountPoints = [
        {
          sourceVolume  = "mcp-servers"
          containerPath = "/app/registry/servers"
          readOnly      = false
        },
        {
          sourceVolume  = "mcp-models"
          containerPath = "/app/registry/models"
          readOnly      = false
        },
        {
          sourceVolume  = "mcp-logs"
          containerPath = "/app/logs"
          readOnly      = false
        }
      ]

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_name             = "/ecs/${local.name_prefix}-registry"
      cloudwatch_log_group_retention_in_days = 30

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:7860/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  }

  volume = {
    mcp-servers = {
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.mcp_efs.id
        access_point_id    = aws_efs_access_point.servers.id
        transit_encryption = "ENABLED"
      }
    }
    mcp-models = {
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.mcp_efs.id
        access_point_id    = aws_efs_access_point.models.id
        transit_encryption = "ENABLED"
      }
    }
    mcp-logs = {
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.mcp_efs.id
        access_point_id    = aws_efs_access_point.logs.id
        transit_encryption = "ENABLED"
      }
    }
  }

  load_balancer = {
    http = {
      target_group_arn = module.alb.target_groups["registry"].arn
      container_name   = "registry"
      container_port   = 80
    }
    gradio = {
      target_group_arn = module.alb.target_groups["gradio"].arn
      container_name   = "registry"
      container_port   = 7860
    }
  }

  subnet_ids = var.private_subnet_ids
  security_group_ingress_rules = {
    alb_80 = {
      description                  = "HTTP port"
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb.security_group_id
    }
    alb_443 = {
      description                  = "HTTPS port"
      from_port                    = 443
      to_port                      = 443
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb.security_group_id
    }
    alb_7860 = {
      description                  = "Gradio port"
      from_port                    = 7860
      to_port                      = 7860
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb.security_group_id
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = local.common_tags

  depends_on = [module.ecs_service_auth, module.keycloak_alb]
}

# ECS Service: Keycloak
module "ecs_service_keycloak" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name         = "${local.name_prefix}-keycloak"
  cluster_arn  = var.ecs_cluster_arn
  cpu          = tonumber(var.cpu)
  memory       = tonumber(var.memory)
  desired_count = var.enable_autoscaling ? var.autoscaling_min_capacity : var.keycloak_replicas
  enable_autoscaling = var.enable_autoscaling
  autoscaling_min_capacity = var.autoscaling_min_capacity
  autoscaling_max_capacity = var.autoscaling_max_capacity
  autoscaling_policies = var.enable_autoscaling ? {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value = var.autoscaling_target_cpu
      }
    }
    memory = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageMemoryUtilization"
        }
        target_value = var.autoscaling_target_memory
      }
    }
  } : {}

  requires_compatibilities = ["FARGATE"]
  capacity_provider_strategy = {
    FARGATE = {
      capacity_provider = "FARGATE"
      weight = 100
      base   = 1
    }
  }

  # Task roles
  create_task_exec_iam_role = true
  task_exec_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }
  create_tasks_iam_role  = true
  tasks_iam_role_policies = {
    SecretsManagerAccess = aws_iam_policy.ecs_secrets_access.arn
  }

  # Enable Service Connect
  service_connect_configuration = {
    namespace = aws_service_discovery_private_dns_namespace.mcp.arn
    service = [{
      client_alias = {
        port     = 8080
        dns_name = "keycloak"
      }
      port_name      = "keycloak"
      discovery_name = "keycloak"
    }]
  }

  # Container definitions
  container_definitions = {
    keycloak = {
      cpu                    = tonumber(var.cpu)
      memory                 = tonumber(var.memory)
      essential              = true
      image                  = var.keycloak_image_uri
      command                = ["start-dev"]
      readonlyRootFilesystem = false

      portMappings = [
        {
          name           = "keycloak"
          containerPort = 8080
          protocol       = "tcp"
        },
        {
          name           = "keycloak-mgmt"
          containerPort = 9000
          protocol       = "tcp"
        }
      ]

      environment = [
        {
          name  = "KC_DB"
          value = "postgres"
        },
        {
          name  = "KC_DB_URL"
          value = "jdbc:postgresql://${module.aurora_postgresql.cluster_endpoint}:${module.aurora_postgresql.cluster_port}/${module.aurora_postgresql.cluster_database_name}"
        },
        {
          name  = "KC_DB_USERNAME"
          value = var.keycloak_db_username
        },
        {
          name  = "KEYCLOAK_ADMIN"
          value = var.keycloak_admin_username
        },
        {
          name  = "KC_HTTP_ENABLED"
          value = "true"
        },
        {
          name  = "KC_HTTP_PORT"
          value = "8080"
        },
        {
          name  = "KC_PROXY"
          value = "edge"
        },
        {
          name  = "KC_FEATURES"
          value = "token-exchange,admin-api"
        }
      ]

      secrets = [
        {
          name      = "KC_DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.keycloak_db_password.arn
        },
        {
          name      = "KEYCLOAK_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.keycloak_admin_password.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "mcp-logs"
          containerPath = "/opt/keycloak/logs"
          readOnly      = false
        }
      ]

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_name             = "/ecs/${local.name_prefix}-keycloak"
      cloudwatch_log_group_retention_in_days = 30

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9000/health/ready || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 5
        startPeriod = 120
      }
    }
  }

  volume = {
    mcp-logs = {
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.mcp_efs.id
        access_point_id    = aws_efs_access_point.logs.id
        transit_encryption = "ENABLED"
      }
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.keycloak_alb.target_groups["keycloak"].arn
      container_name   = "keycloak"
      container_port   = 8080
    }
  }

  subnet_ids = var.private_subnet_ids
  security_group_ingress_rules = {
    alb_8080 = {
      description                  = "Keycloak port"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.keycloak_alb.security_group_id
    }
    alb_9000 = {
      description                  = "Keycloak management port"
      from_port                    = 9000
      to_port                      = 9000
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.keycloak_alb.security_group_id
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = local.common_tags

  depends_on = [module.aurora_postgresql, module.keycloak_alb]
}