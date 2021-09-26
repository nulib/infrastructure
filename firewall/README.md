## Description

This terraform project includes the resources required to set up the WAF ACL(s) needed to provide access control to NUL projects running in the staging environment.

## Secrets

* `firewall_type` – The type of firewall to create (`IP` for NUL IPs, `SECURITY` for managed security rulesets)
* `nul_ips` – A list of IP ranges representing the NUL staff offices and VPN
* `rdc_home_ips` – A list of IP addresses representing home offices of NUL RDC staffers for convenience
* `resources` – A map of indicating the resources to be protected
  * Example: `{ name = "my-app", arn = "arn:aws:elasticloadbalancing:..." }`

## Outputs

* None

## Remote State

```
data "terraform_remote_state" "firewall" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/firewall.tfstate"
  }
}
```
