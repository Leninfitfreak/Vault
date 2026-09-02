variable "mounts" {
  description = "PKI secrets engine mounts."
  type = map(object({
    description           = string
    default_ttl_seconds   = number
    max_ttl_seconds       = number
    ca_common_name        = string
    ca_ttl                = string
    organization          = string
    issuing_certificates  = list(string)
    crl_distribution_urls = list(string)
  }))
  default = {}
}

variable "roles" {
  description = "PKI issuance roles."
  type = map(object({
    mount              = string
    allowed_domains    = list(string)
    allow_bare_domains = bool
    allow_subdomains   = bool
    server_flag        = bool
    client_flag        = bool
    key_type           = string
    key_bits           = number
    ttl                = string
    max_ttl            = string
  }))
  default = {}
}
