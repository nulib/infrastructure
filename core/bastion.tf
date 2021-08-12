data "aws_security_group" "bastion" {
  name = "${local.namespace}-bastion"
}
data "aws_instance" "bastion" {
  filter {
    name   = "tag:Name"
    values = ["${local.namespace}-bastion"]
  }  
}
