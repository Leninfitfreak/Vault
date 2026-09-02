resource "vault_mount" "pki" {
  for_each = var.mounts

  path                      = each.key
  type                      = "pki"
  description               = each.value.description
  default_lease_ttl_seconds = each.value.default_ttl_seconds
  max_lease_ttl_seconds     = each.value.max_ttl_seconds
}

resource "vault_pki_secret_backend_root_cert" "root" {
  for_each = var.mounts

  backend     = vault_mount.pki[each.key].path
  type        = "internal"
  common_name = each.value.ca_common_name
  ttl         = each.value.ca_ttl
  key_type    = "rsa"
  key_bits    = 2048

  organization = each.value.organization
}

resource "vault_pki_secret_backend_config_urls" "urls" {
  for_each = var.mounts

  backend                 = vault_mount.pki[each.key].path
  issuing_certificates    = each.value.issuing_certificates
  crl_distribution_points = each.value.crl_distribution_urls

  depends_on = [vault_pki_secret_backend_root_cert.root]
}

resource "vault_pki_secret_backend_role" "this" {
  for_each = var.roles

  backend                     = vault_mount.pki[each.value.mount].path
  name                        = each.key
  allowed_domains             = each.value.allowed_domains
  allow_bare_domains          = each.value.allow_bare_domains
  allow_subdomains            = each.value.allow_subdomains
  allow_wildcard_certificates = false
  allow_any_name              = false
  enforce_hostnames           = true
  require_cn                  = true
  use_csr_common_name         = false
  use_csr_sans                = false
  allow_ip_sans               = false
  server_flag                 = each.value.server_flag
  client_flag                 = each.value.client_flag
  key_type                    = each.value.key_type
  key_bits                    = each.value.key_bits
  ttl                         = each.value.ttl
  max_ttl                     = each.value.max_ttl
  generate_lease              = true
  no_store                    = false

  depends_on = [
    vault_pki_secret_backend_root_cert.root,
    vault_pki_secret_backend_config_urls.urls
  ]
}
