variable "actions_enabled" {
  type    = bool
  default = false
}

variable "load_balancers" {
  type    = list(string)
  default = []
}

variable "alarm_actions" {
  type    = list(string)
  default = []
}

variable "services" {
  type    = map(list(string))
  default = {}
}

variable "slack_webhook" {
  type    = map(string)
  default = {
    channel   = ""
    url       = ""
    username  = ""
  }
}

variable "status_zone_name" {
  type    = string
}