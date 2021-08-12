output "address" {
  value = aws_db_instance.db.address
}

output "port" {
  value = aws_db_instance.db.port
}

output "client_security_group" {
  value = aws_security_group.db_client.id
}

output "admin_user" {
  value = "dbadmin"
}

output "admin_password" {
  value = random_string.master_password.result
}
