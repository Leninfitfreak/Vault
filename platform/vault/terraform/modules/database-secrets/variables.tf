variable "mounts" {
  description = "Vault database secrets engine mounts."
  type = map(object({
    description               = string
    default_lease_ttl_seconds = number
    max_lease_ttl_seconds     = number
  }))
  default = {}
}

variable "connections" {
  description = "Vault database connections. Bootstrap passwords use write-only provider fields."
  type = map(object({
    mount                   = string
    plugin_name             = string
    allowed_roles           = list(string)
    verify_connection       = bool
    connection_url          = string
    username                = string
    password_wo_version     = number
    max_open_connections    = optional(number)
    max_idle_connections    = optional(number)
    max_connection_lifetime = optional(number)
  }))
  default = {}
}

variable "bootstrap_password" {
  description = "Write-only database bootstrap password supplied externally."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "roles" {
  description = "Vault database roles that issue dynamic credentials."
  type = map(object({
    mount                 = string
    db_name               = string
    creation_statements   = list(string)
    revocation_statements = list(string)
    default_ttl           = number
    max_ttl               = number
  }))
  default = {}
}
