output "policy_names" {
  description = "Terraform-managed Vault policy names."
  value       = module.policies.policy_names
}

output "kv_v2_mount_paths" {
  description = "Terraform-managed KV v2 mount paths."
  value       = keys(var.kv_v2_mounts)
}

output "database_secret_mount_paths" {
  description = "Terraform-managed database secrets engine mount paths."
  value       = module.database_secrets.mount_paths
}

output "database_connection_names" {
  description = "Terraform-managed Vault database connection names."
  value       = module.database_secrets.connection_names
}

output "database_role_names" {
  description = "Terraform-managed Vault database dynamic role names."
  value       = module.database_secrets.role_names
}

output "pki_mount_paths" {
  description = "Terraform-managed PKI mount paths."
  value       = module.pki.mount_paths
}

output "pki_role_names" {
  description = "Terraform-managed PKI role names."
  value       = module.pki.role_names
}

output "kubernetes_auth_path" {
  description = "Kubernetes auth path when enabled."
  value       = try(module.kubernetes_auth[0].backend_path, null)
}

output "kubernetes_auth_role_names" {
  description = "Terraform-managed Kubernetes auth role names."
  value       = try(module.kubernetes_auth[0].role_names, [])
}
