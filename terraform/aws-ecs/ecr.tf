locals {
  project_root = abspath("${path.root}/../..")
}

resource "aws_ecr_repository" "registry" {
  count = var.use_private_ecr ? 1 : 0

  name                 = "${var.name}-registry"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "auth" {
  count = var.use_private_ecr ? 1 : 0

  name                 = "${var.name}-auth"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "null_resource" "build_registry_image" {
  count = var.use_private_ecr ? 1 : 0

  triggers = {
    tag   = var.local_image_tag
    force = var.local_image_force_rebuild
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      cd ${local.project_root}
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.registry[0].repository_url}
      docker build -f docker/Dockerfile.registry -t ${aws_ecr_repository.registry[0].repository_url}:${var.local_image_tag} .
      docker push ${aws_ecr_repository.registry[0].repository_url}:${var.local_image_tag}
    EOT
  }
}

resource "null_resource" "build_auth_image" {
  count = var.use_private_ecr ? 1 : 0

  triggers = {
    tag   = var.local_image_tag
    force = var.local_image_force_rebuild
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      cd ${local.project_root}
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.auth[0].repository_url}
      docker build -f docker/Dockerfile.auth -t ${aws_ecr_repository.auth[0].repository_url}:${var.local_image_tag} .
      docker push ${aws_ecr_repository.auth[0].repository_url}:${var.local_image_tag}
    EOT
  }
}

locals {
  default_registry_image    = var.registry_image_override != "" ? var.registry_image_override : "mcpgateway/registry:latest"
  default_auth_server_image = var.auth_server_image_override != "" ? var.auth_server_image_override : "mcpgateway/auth-server:latest"

  registry_repo_url = try(aws_ecr_repository.registry[0].repository_url, "")
  auth_repo_url     = try(aws_ecr_repository.auth[0].repository_url, "")

  registry_build_id = try(null_resource.build_registry_image[0].id, "")
  auth_build_id     = try(null_resource.build_auth_image[0].id, "")

  registry_image_uri = var.use_private_ecr ? replace("${local.registry_repo_url}:${var.local_image_tag}@@${local.registry_build_id}", "@@${local.registry_build_id}", "") : local.default_registry_image

  auth_server_image_uri = var.use_private_ecr ? replace("${local.auth_repo_url}:${var.local_image_tag}@@${local.auth_build_id}", "@@${local.auth_build_id}", "") : local.default_auth_server_image
}
