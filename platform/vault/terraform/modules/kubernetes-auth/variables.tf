variable "backend_path" {
  description = "Path where the Kubernetes auth method is mounted."
  type        = string
  default     = "kubernetes"
}

variable "description" {
  description = "Description for the Kubernetes auth method."
  type        = string
  default     = "Kubernetes workload identity authentication"
}

variable "kubernetes_host" {
  description = "Kubernetes API address reachable by Vault."
  type        = string
}

variable "disable_local_ca_jwt" {
  description = "Whether Vault should avoid using its in-pod local service account token and CA."
  type        = bool
  default     = false
}

variable "workloads" {
  description = "Kubernetes workloads allowed to authenticate to Vault, keyed by Vault role name."
  type = map(object({
    bound_service_account_names      = list(string)
    bound_service_account_namespaces = list(string)
    token_policies                   = list(string)
    token_ttl                        = number
    token_max_ttl                    = number
    audience                         = optional(string)
  }))
  default = {}
}
