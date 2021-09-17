data "aws_ssm_parameter" "values" {
  name              = "/${var.namespace}/${var.path}"
  with_decryption   = true
}
