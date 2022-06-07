variable "postgres_version" {
  type    = string
  default = "13.4"
}

variable "allocated_storage" {
  type    = number
  default = 100
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

