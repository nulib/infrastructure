locals {
  zookeeper_version = split(":", var.zookeeper_image)[1]
}

data "aws_ecr_repository" "zookeeper" {
  name = "zookeeper"
}

resource "docker_image" "zookeeper" {
  name         = "${data.aws_ecr_repository.zookeeper.repository_url}:${local.zookeeper_version}"

  build {
    context      = "${path.module}/zk-image"

    build_args = {
      ZK_VERSION = local.zookeeper_version
    }
  }

  triggers = {
    entrypoint = filemd5("${path.module}/zk-image/docker-entrypoint.sh")
  }
}

resource "docker_registry_image" "zookeeper" {
  name            = docker_image.zookeeper.name
  keep_remotely   = true
}