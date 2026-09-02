module "policies" {
  source = "../../modules/policies"

  policies = var.policies
}

module "kv_v2" {
  source = "../../modules/kv-v2"

  mounts = var.kv_v2_mounts
}

module "database_secrets" {
  source = "../../modules/database-secrets"

  mounts             = var.database_secrets.mounts
  connections        = var.database_secrets.connections
  roles              = var.database_secrets.roles
  bootstrap_password = var.database_bootstrap_password
}

module "pki" {
  source = "../../modules/pki"

  mounts = var.pki.mounts
  roles  = var.pki.roles
}

module "kubernetes_auth" {
  count  = var.kubernetes_auth.enabled ? 1 : 0
  source = "../../modules/kubernetes-auth"

  backend_path         = var.kubernetes_auth.backend_path
  kubernetes_host      = var.kubernetes_auth.kubernetes_host
  disable_local_ca_jwt = var.kubernetes_auth.disable_local_ca_jwt
  workloads            = var.kubernetes_auth.workload_identities
}
