## Description

This terraform project includes the resources required to set up the WAF ACL(s) needed to provide access control to NUL projects running in the staging environment.

## Secrets

* `firewall_type` – The type of firewall to create (`IP` for NUL IPs, `SECURITY` for managed security rulesets)
* `load_balancers` – The ARNs of the application load balancers to protect
* `nul_ips` – A list of IP ranges representing the NUL staff offices and VPN
* `rdc_home_ips` – A list of IP addresses representing home offices of NUL RDC staffers for convenience

## Outputs

* None

## Remote State

```
data "terraform_remote_state" "staging_waf" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/staging-waf.tfstate"
  }
}
```
