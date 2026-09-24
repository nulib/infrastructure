variable "solr_cluster_size" {
  type    = number
  default = 4
}

variable "backup_schedule" {
  type    = string
  default = null
}

variable "honeybadger_api_key" {
  type    = string
  default = null
}

variable "honeybadger_env" {
  type    = string
  default = null
}

variable "honeybadger_checkin_id" {
  type    = string
  default = null
}

variable "zookeeper_image" {
  type    = string
  default = "public.ecr.aws/docker/library/zookeeper:3.9"
}

variable "zookeeper_sidecar_image" {
  type    = string
  default = "public.ecr.aws/aws-cli/aws-cli:latest"
}

variable "solr_image" {
  type    = string
  default = "public.ecr.aws/docker/library/solr:9"
}

variable "default_zk_password" {
  type    = string
}

variable "solr_cpu" {
  type    = number
  default = 1024
}

variable "solr_task_memory" {
  type    = number
  default = 2048
}

variable "solr_heap" {
  type    = number
  default = 1000
}

variable "solr_sidecar_image" {
  type    = string
  default = "public.ecr.aws/docker/library/python:3-slim"
}
