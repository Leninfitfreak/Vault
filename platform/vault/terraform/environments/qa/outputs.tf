output "policy_names" {
  description = "Terraform-managed Vault policy names."
  value       = module.policies.policy_names
}
