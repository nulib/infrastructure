## Description

This terraform project creates CloudWatch alarms to monitor stack resources and applications.

## Secrets

* `actions_enabled` – Boolean value indicating whether to enable actions for alarms
* `alarm_actions` – The list of ARNS to be notified in an alarm state
* `load_balancers` – The names of the application load balancers to monitor
* `services` – A map of indicating which services to monitor
  * Example: `{ "meadow" = ["meadow"], "arch" = ["arch-webapp", "arch-worker"] }` 

## Outputs

* None

## Remote State

```
data "terraform_remote_state" "monitoring" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/monitoring.tfstate"
  }
}
```
