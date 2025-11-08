# IAM resources for MCP Gateway Registry ECS services

# IAM policy for ECS tasks to access Secrets Manager
resource "aws_iam_policy" "ecs_secrets_access" {
  name_prefix = "${local.name_prefix}-ecs-secrets-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = concat([
          aws_secretsmanager_secret.secret_key.arn,
          aws_secretsmanager_secret.admin_password.arn,
        ], local.keycloak_secret_arns)
      }
    ]
  })

  tags = local.common_tags
}