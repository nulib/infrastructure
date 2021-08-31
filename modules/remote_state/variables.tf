variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "component" {
  type    = string
}

variable "state_bucket" {
  type    = string
  default = "nulterra-state-sandbox"
}
