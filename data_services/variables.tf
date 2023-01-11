variable "postgres_version" {
  type    = string
  default = "13.4"
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
