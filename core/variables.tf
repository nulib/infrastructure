variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "cidr_block" {
  type    = string
  default = "10.1.0.0/16"
}

variable "environment" {
  type    = string
  default = ""
}

variable "hosted_zone_name" {
  type    = string
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.1.2.0/24", "10.1.4.0/24", "10.1.6.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.1.1.0/24", "10.1.3.0/24", "10.1.5.0/24"]
}

variable "stack_name" {
  type    = string
  default = "stack"
}

variable "tags" {
  type    = map(string)
  default = {}
}
