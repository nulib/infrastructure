variable "mappings" {
  type    = map(string)
  default = {}
}

variable "response_status" {
  type    = number
  default = 302
}

variable "ssl_certificate_arn" {
  type    = string
}
