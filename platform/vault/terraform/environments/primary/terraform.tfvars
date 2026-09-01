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
  orders-service-api-key-read = {
    rules = <<-EOT
      path "kv/data/primary/orders/orders-service/application" {
        capabilities = ["read"]
      }
    EOT
  }
}

kv_v2_mounts = {
  kv = {
    description = "Reusable KV v2 engine for static application secrets"
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
    orders-service-vso = {
      bound_service_account_names      = ["orders-service-vso"]
      bound_service_account_namespaces = ["orders"]
      token_policies                   = ["orders-service-api-key-read"]
      token_ttl                        = 600
      token_max_ttl                    = 1800
      audience                         = "vault"
    }
  }
}
