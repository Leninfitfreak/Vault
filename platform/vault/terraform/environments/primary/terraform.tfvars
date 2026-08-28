vault_address = "http://127.0.0.1:8200"

policies = {
  platform-readiness = {
    rules = <<-EOT
      path "sys/health" {
        capabilities = ["read"]
      }
    EOT
  }
}
