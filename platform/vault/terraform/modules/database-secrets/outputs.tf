output "mount_paths" {
  description = "Database secrets engine mount paths."
  value       = [for mount in vault_mount.database : mount.path]
}

output "connection_names" {
  description = "Vault database connection names."
  value       = [for connection in vault_database_secret_backend_connection.this : connection.name]
}

output "role_names" {
  description = "Vault database role names."
  value       = [for role in vault_database_secret_backend_role.this : role.name]
}
