output "vars" {
  value = nonsensitive(merge(jsondecode(var.defaults), jsondecode(data.aws_ssm_parameter.values.value)))
}