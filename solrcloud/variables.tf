variable "zookeeper_ensemble_size" {
  type    = number
  default = 3
}

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
  default = "zookeeper:3.9"
}

variable "solr_image" {
  type    = string
  default = "solr:9"
}

variable "default_zk_password" {
  type    = string
}
