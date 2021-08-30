output "postgres" {
  value = {
    address                 = aws_db_instance.db.address
    port                    = aws_db_instance.db.port
    client_security_group   = aws_security_group.db_client.id
    admin_user              = "dbadmin"
    admin_password          = random_string.db_master_password.result
  }
}
