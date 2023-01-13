locals {
  repositories = toset(["arch", "avr", "fcrepo4", "meadow", "solr", "zookeeper"])
}

resource "aws_ecr_repository" "nulib_images" {
  for_each                = local.repositories
  name                    = each.key
  image_tag_mutability    = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "nulib_image_expiration" {
  for_each    = local.repositories
  repository  = aws_ecr_repository.nulib_images[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type        = "expire"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_role" "task_execution_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_iam_policy" "ecs_exec_command" {
  name = "allow-ecs-exec"
}
