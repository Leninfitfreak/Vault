resource "vault_mount" "database" {
  for_each = var.mounts

  path                      = each.key
  type                      = "database"
  description               = each.value.description
  default_lease_ttl_seconds = each.value.default_lease_ttl_seconds
  max_lease_ttl_seconds     = each.value.max_lease_ttl_seconds
}

resource "vault_database_secret_backend_connection" "this" {
  for_each = var.connections

  backend           = vault_mount.database[each.value.mount].path
  name              = each.key
  allowed_roles     = each.value.allowed_roles
  plugin_name       = each.value.plugin_name
  verify_connection = each.value.verify_connection

  postgresql {
    connection_url          = each.value.connection_url
    username                = each.value.username
    password_wo             = var.bootstrap_password
    password_wo_version     = each.value.password_wo_version
    max_open_connections    = each.value.max_open_connections
    max_idle_connections    = each.value.max_idle_connections
    max_connection_lifetime = each.value.max_connection_lifetime
  }
}

resource "vault_database_secret_backend_role" "this" {
  for_each = var.roles

  backend               = vault_mount.database[each.value.mount].path
  name                  = each.key
  db_name               = vault_database_secret_backend_connection.this[each.value.db_name].name
  creation_statements   = each.value.creation_statements
  revocation_statements = each.value.revocation_statements
  default_ttl           = each.value.default_ttl
  max_ttl               = each.value.max_ttl
}
