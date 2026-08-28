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
