variable "certificate_arn" {
  type    = string
  default = ""
}

variable "mappings" {
  type    = map(map(string))
  default = {}
}

variable "response_status" {
  type    = number
  default = 302
}
