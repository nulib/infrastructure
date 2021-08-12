resource "aws_ecr_repository" "nulib_images" {
  for_each                = toset(["arch", "avr", "fcrepo4", "meadow", "solr", "zookeeper"])
  name                    = each.key
  image_tag_mutability    = "MUTABLE"
  tags                    = merge(local.tags)
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
