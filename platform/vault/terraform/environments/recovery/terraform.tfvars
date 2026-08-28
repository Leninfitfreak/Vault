vault_address = "http://127.0.0.1:8200"

policies = {}

kubernetes_auth = {
  enabled              = false
  backend_path         = "kubernetes"
  kubernetes_host      = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt = false
  workload_identities  = {}
}
