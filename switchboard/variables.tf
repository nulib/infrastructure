variable "mappings" {
  type    = map(string)
  default = {}
}

variable "response_status" {
  type    = number
  default = 302
}
