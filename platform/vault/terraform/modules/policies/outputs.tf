output "policy_names" {
  description = "Terraform-managed Vault policy names."
  value       = sort(keys(vault_policy.this))
}
