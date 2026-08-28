module "policies" {
  source = "../../modules/policies"

  policies = var.policies
}

module "kubernetes_auth" {
  count  = var.kubernetes_auth.enabled ? 1 : 0
  source = "../../modules/kubernetes-auth"

  backend_path         = var.kubernetes_auth.backend_path
  kubernetes_host      = var.kubernetes_auth.kubernetes_host
  disable_local_ca_jwt = var.kubernetes_auth.disable_local_ca_jwt
  workloads            = var.kubernetes_auth.workload_identities
}
