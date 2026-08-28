vault_address = "http://127.0.0.1:8200"

policies = {
  platform-readiness = {
    rules = <<-EOT
      path "sys/health" {
        capabilities = ["read"]
      }
    EOT
  }
  orders-service-runtime = {
    rules = <<-EOT
      path "sys/health" {
        capabilities = ["read"]
      }
    EOT
  }
}

kubernetes_auth = {
  enabled              = true
  backend_path         = "kubernetes"
  kubernetes_host      = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt = false

  workload_identities = {
    orders-service = {
      bound_service_account_names      = ["orders-service"]
      bound_service_account_namespaces = ["orders"]
      token_policies                   = ["orders-service-runtime"]
      token_ttl                        = 900
      token_max_ttl                    = 1800
      audience                         = "vault"
    }
  }
}
