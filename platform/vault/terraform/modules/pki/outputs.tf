output "mount_paths" {
  description = "Terraform-managed PKI mount paths."
  value       = keys(var.mounts)
}

output "role_names" {
  description = "Terraform-managed PKI role names."
  value       = keys(var.roles)
}
