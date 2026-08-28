resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = var.backend_path
  description = var.description
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = var.kubernetes_host
  disable_local_ca_jwt = var.disable_local_ca_jwt
}

resource "vault_kubernetes_auth_backend_role" "workloads" {
  for_each = var.workloads

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = each.value.bound_service_account_names
  bound_service_account_namespaces = each.value.bound_service_account_namespaces
  token_policies                   = each.value.token_policies
  token_ttl                        = each.value.token_ttl
  token_max_ttl                    = each.value.token_max_ttl
  audience                         = each.value.audience
}
