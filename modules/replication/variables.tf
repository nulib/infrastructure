variable "source_bucket_arn" {
  type    = string
}

variable "tags" {
  type    = map(string)
  default = {}
}