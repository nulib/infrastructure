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

variable "embedding_dimensions" {
  type = number
}
