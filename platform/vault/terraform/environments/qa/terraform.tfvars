vault_address = "http://127.0.0.1:8200"

policies = {}

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
  workload_identities  = {}
}
