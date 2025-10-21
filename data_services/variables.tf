variable "aurora_engine_version" {
  type    = string
  default = "16.6"
}

variable "aurora_min_capacity" {
  type    = number
  default = 0.5
}

variable "aurora_max_capacity" {
  type    = number
  default = 8
}

variable "postgres_version" {
  type    = string
  default = "13.15"
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
