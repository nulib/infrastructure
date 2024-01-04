variable "firewall_type" {
  type    = string
  default = ""
}

variable "allowed_user_agents" {
  type    = list
  default = []
}

variable "high_traffic_ips" {
  type    = list
  default = []
}

variable "global_rate_limit" {
  type    = number
  default = 1000
}

variable "resources" {
  type    = map
  default = {}
}
