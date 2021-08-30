variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  type    = string
  default = "nulterra-state-sandbox"
}

variable "postgres_version" {
  type    = string
  default = "13.3"
}

variable "allocated_storage" {
  type    = number
  default = 100
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}