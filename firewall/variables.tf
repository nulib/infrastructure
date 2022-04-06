variable "firewall_type" {
  type    = string
  default = ""
}

variable "nul_ips" {
  type    = list
  default = []
}

variable "nul_ips_v6" {
  type    = list
  default = []
}

variable "rdc_home_ips" {
  type    = list
  default = []
}

variable "resources" {
  type    = map
  default = {}
}
