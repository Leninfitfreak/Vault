variable "vault_address" {
  description = "Vault API address for this environment. Credentials are supplied externally."
  type        = string
}

variable "policies" {
  description = "Non-secret Vault policies for this environment."
  type = map(object({
    rules = string
  }))
  default = {}
}

variable "kv_v2_mounts" {
  description = "KV v2 mounts for static application secrets. Payload is managed outside Terraform."
  type = map(object({
    description = string
  }))
  default = {}
}

variable "kubernetes_auth" {
  description = "Kubernetes auth configuration for this environment."
  type = object({
    enabled              = bool
    backend_path         = string
    kubernetes_host      = string
    disable_local_ca_jwt = bool
    workload_identities = map(object({
      bound_service_account_names      = list(string)
      bound_service_account_namespaces = list(string)
      token_policies                   = list(string)
      token_ttl                        = number
      token_max_ttl                    = number
      audience                         = optional(string)
    }))
  })
  default = {
    enabled              = false
    backend_path         = "kubernetes"
    kubernetes_host      = "https://kubernetes.default.svc:443"
    disable_local_ca_jwt = false
    workload_identities  = {}
  }
}
