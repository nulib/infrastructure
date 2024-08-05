variable "postgres_version" {
  type    = string
  default = "13.13"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "ldap_config" {
  type    = map(string)
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
  type = string
}

variable "model_requirements" {
  type    = list(string)
  default = []
}

variable "sagemaker_configurations" {
  type = map(object({
    name                    = string
    memory                  = number
    provisioned_concurrency = number
    max_concurrency         = number
  }))    
}