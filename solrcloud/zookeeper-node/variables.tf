variable "id" {
  description = "ZooKeeper server id (myid), 1-based"
  type        = number
}

variable "service_name" {
  description = "ECS service name; kept as-is from the original count-based services (zookeeper-0..2)"
  type        = string
}

variable "cluster_id"                 { type = string }
variable "image"                      { type = string }
variable "sidecar_image"              { type = string }
variable "zoo_servers"                { type = string }
variable "admin_auth"                 { type = string }
variable "backup_bucket"              { type = string }
variable "backup_interval"            { type = number }
variable "task_role_arn"              { type = string }
variable "execution_role_arn"         { type = string }
variable "log_group"                  { type = string }
variable "region"                     { type = string }
variable "subnet_ids"                 { type = list(string) }
variable "security_group_ids"         { type = list(string) }
variable "discovery_namespace_id"     { type = string }
