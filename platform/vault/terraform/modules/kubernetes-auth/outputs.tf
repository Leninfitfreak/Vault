output "backend_path" {
  description = "Kubernetes auth backend path."
  value       = vault_auth_backend.kubernetes.path
}

output "role_names" {
  description = "Terraform-managed Kubernetes auth role names."
  value       = sort(keys(vault_kubernetes_auth_backend_role.workloads))
}
