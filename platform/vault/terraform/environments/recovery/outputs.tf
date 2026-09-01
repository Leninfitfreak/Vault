output "policy_names" {
  description = "Terraform-managed Vault policy names."
  value       = module.policies.policy_names
}

output "kv_v2_mount_paths" {
  description = "Terraform-managed KV v2 mount paths."
  value       = keys(var.kv_v2_mounts)
}

output "kubernetes_auth_path" {
  description = "Kubernetes auth path when enabled."
  value       = try(module.kubernetes_auth[0].backend_path, null)
}

output "kubernetes_auth_role_names" {
  description = "Terraform-managed Kubernetes auth role names."
  value       = try(module.kubernetes_auth[0].role_names, [])
}
