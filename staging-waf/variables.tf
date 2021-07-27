variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "load_balancers" {
  type    = list(string)
}

variable "nul_ips" {
  type    = list(string)
  default = [
    "129.105.184.0/24",
    "165.124.201.96/28",
    "165.124.144.0/23",
    "165.124.199.32/29",
    "165.124.200.24/29",
    "165.124.202.0/24",
    "165.124.160.0/21",
    "129.105.29.0/24",
    "129.105.112.64/26",
    "129.105.203.0/24"
  ]
}

variable "rdc_home_ips" {
  type    = list(string)
}