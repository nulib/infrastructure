variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  type    = string
  default = "nulterra-state-sandbox"
}

variable "zookeeper_ensemble_size" {
  type    = number
  default = 3
}

variable "solr_cluster_size" {
  type    = number
  default = 4
}