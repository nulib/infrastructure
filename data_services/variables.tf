variable "postgres_version" {
  type    = string
  default = "13.13"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "opensearch_cluster_nodes" {
  type    = number
  default = 3
}

variable "opensearch_volume_size" {
  type    = number
  default = 10
}

variable "model_repository" {
  type    = string
}

variable "sagemaker_inference_memory" {
  type    = number
  default = 4096
}

variable "sagemaker_inference_provisioned_concurrency" {
  type    = number
  default = 0
}

variable "sagemaker_inference_max_concurrency" {
  type    = number
  default = 20
}