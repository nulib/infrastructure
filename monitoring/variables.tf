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
