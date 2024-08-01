## Description

This terraform project includes the resources required to set up the WAF ACL(s) needed to provide access control to NUL projects running in the staging environment.

## Secrets

* `allowed_user_agents` – The list of user agents to allow through without bot control
* `firewall_type` – The type of firewall to create (`IP` for NUL IPs, `SECURITY` for managed security rulesets)
* `high_traffic_ips` – Known high-traffic IPs to block
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
