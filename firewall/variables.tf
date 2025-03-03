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
  type        = number
  description = "Global rate limit for requests"
  default     = 2000
}


variable "high_traffic_ips_aug2024" {
  type        = list(string)
  description = "List of High Traffic IPs added by Marek August 2024"
  default     = []
}

variable "honeybadger_tokens" {
  type    = list(string)
  default = []
}

variable "nul_ips" {
  type    = map(list(string))
  default = {v4 = [], v6 = []}
}

variable "nul_staff_ips" {
  type    = list(string)
  default = []
}

variable "rate_limited_country_codes" {
  type    = list(string)
  default = []
}

variable "resources" {
  type    = map
  default = {}
}
