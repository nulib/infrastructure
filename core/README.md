## Description

This terraform project includes the core resources that form the base of NUL's shared infrastructure and application stack. These resources include:

* The Virtual Private Cloud (VPC)
* Elastic Container Registry (ECR) Repositories
* Redis Instance
* Elasticsearch

## Variables

* `aws_region` - The region to create resources in (default: `us-east-1`) 
* `availability_zones` - A list of availability zones to assign to the VPC (default: `[us-east-1a, us-east-1b, us-east-1c]`)
* `cidr_block` - The CIDR block to use for the VPC (default: `10.1.0.0/16`)
* `environment` - The environment name or code (default: the first letter of the terraform workspace name, e.g. `s` or `p`)
* `hosted_zone_name` - The base DNS zone for resources within the VPC
* `public_subnets` - The list of public subnets to be created within the VPC (default: `["10.1.2.0/24", "10.1.4.0/24", "10.1.6.0/24"]`)
* `private_subnets` - The list of private subnets to be created within the VPC (default: `["10.1.1.0/24", "10.1.3.0/24", "10.1.5.0/24"]`)
* `stack_name` - A name for the stack
* `tags` - A map of tags that will be applied to all resources within the stack

## Outputs

* `bastion.instance` - The ID of the bastion host EC2 instance
* `bastion.security_group` - The ID of the bastion host security group
* `stack.environment`- The value of the `environment` variable
* `stack.name` - The value of the `stack_name` variable
* `stack.namespace` - The stack name and environment, joined by `-`
* `stack.tags` - The map of tags supplied in the `tags` variable
* `vpc.cidr_block` - The CIDR block of the VPC
* `vpc.http_security_group_id` - The ID of the shared HTTP security group that allows HTTP access to the entire VPC
* `vpc.id` - The ID of the VPC
* `vpc.private_dns_zone.id` - The ID of the private Route53 DNS zone
* `vpc.private_dns_zone.name` - The name of the private Route53 DNS zone
* `vpc.private_subnets.cidr_blocks` - The list of private subnets in the VPC
* `vpc.private_subnets.ids` - The list of IDs of private subnets in the VPC
* `vpc.public_dns_zone.id` - The ID of the public Route53 DNS zone
* `vpc.public_dns_zone.name` - The name of the public Route53 DNS zone
* `vpc.public_subnets.cidr_blocks` - The list of public subnets in the VPC
* `vpc.public_subnets.ids` - The list of IDs of public subnets in the VPC
* `vpc.service_discovery_dns_zone.id` - The ID of the internal Cloud Map DNS zone
* `vpc.service_discovery_dns_zone.name` - The name of the internal Cloud Map DNS zone

## Remote State

```
data "terraform_remote_state" "core" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/core.tfstate"
    region = var.aws_region
  }
}
```
