variable "postgres_version" {
  type    = string
  default = "13.13"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "ldap_config" {
  type = map(string)
}

variable "opensearch_cluster_nodes" {
  type    = number
  default = 3
}

variable "opensearch_volume_size" {
  type    = number
  default = 10
}

variable "embedding_model_name" {
  type = string
}

<<<<<<< HEAD
variable "model_requirements" {
  type    = list(string)
  default = []
=======
variable "embedding_dimensions" {
  type = number
>>>>>>> 9b6d2ca (Replace SageMaker with Bedrock connector for generating embeddings)
}
