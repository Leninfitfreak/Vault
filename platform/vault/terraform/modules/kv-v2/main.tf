resource "vault_mount" "this" {
  for_each = var.mounts

  path        = each.key
  type        = "kv-v2"
  description = each.value.description

  options = {
    version = "2"
  }
}
