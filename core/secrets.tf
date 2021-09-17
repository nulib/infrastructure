locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/core"
  defaults  = jsonencode({
    availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
    cidr_block            = "10.1.0.0/16"
    environment           = ""
    public_subnets        = ["10.1.2.0/24", "10.1.4.0/24", "10.1.6.0/24"]
    private_subnets       = ["10.1.1.0/24", "10.1.3.0/24", "10.1.5.0/24"]
    stack_name            = "stack"
    tags                  = {}
  })
}
