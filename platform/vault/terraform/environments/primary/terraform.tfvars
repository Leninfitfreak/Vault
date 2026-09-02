vault_address = "http://127.0.0.1:8200"

policies = {
  platform-readiness = {
    rules = <<-EOT
      path "sys/health" {
        capabilities = ["read"]
      }
    EOT
  }
  orders-service-runtime = {
    rules = <<-EOT
      path "sys/health" {
        capabilities = ["read"]
      }
    EOT
  }
  orders-service-api-key-read = {
    rules = <<-EOT
      path "kv/data/primary/orders/orders-service/application" {
        capabilities = ["read"]
      }
    EOT
  }
  orders-service-database-credentials-read = {
    rules = <<-EOT
      path "database/creds/orders-service-db" {
        capabilities = ["read"]
      }
    EOT
  }
  orders-service-pki-server-issue = {
    rules = <<-EOT
      path "pki/issue/orders-service-server" {
        capabilities = ["update"]
      }
    EOT
  }
  frontend-service-pki-client-issue = {
    rules = <<-EOT
      path "pki/issue/frontend-service-client" {
        capabilities = ["update"]
      }
    EOT
  }
}

kv_v2_mounts = {
  kv = {
    description = "Reusable KV v2 engine for static application secrets"
  }
}

database_secrets = {
  mounts = {
    database = {
      description               = "Dynamic database credentials for application workloads"
      default_lease_ttl_seconds = 1200
      max_lease_ttl_seconds     = 3600
    }
  }

  connections = {
    orders-postgresql = {
      mount                   = "database"
      plugin_name             = "postgresql-database-plugin"
      allowed_roles           = ["orders-service-db"]
      verify_connection       = true
      connection_url          = "postgresql://{{username}}:{{password}}@postgresql.orders.svc.cluster.local:5432/orders?sslmode=disable"
      username                = "orders_user"
      password_wo_version     = 1
      max_open_connections    = 4
      max_idle_connections    = 2
      max_connection_lifetime = 300
    }
  }

  roles = {
    orders-service-db = {
      mount   = "database"
      db_name = "orders-postgresql"
      creation_statements = [
        "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION",
        "GRANT CONNECT ON DATABASE orders TO \"{{name}}\"",
        "GRANT USAGE ON SCHEMA public TO \"{{name}}\""
      ]
      revocation_statements = [
        "REVOKE ALL PRIVILEGES ON DATABASE orders FROM \"{{name}}\"",
        "REVOKE ALL PRIVILEGES ON SCHEMA public FROM \"{{name}}\"",
        "DROP OWNED BY \"{{name}}\"",
        "DROP ROLE IF EXISTS \"{{name}}\""
      ]
      default_ttl = 1200
      max_ttl     = 3600
    }
  }
}

pki = {
  mounts = {
    pki = {
      description           = "Local POC PKI for orders-service mTLS certificates"
      default_ttl_seconds   = 300
      max_ttl_seconds       = 3600
      ca_common_name        = "Vault Local POC Root CA"
      ca_ttl                = "24h"
      organization          = "Local Vault POC"
      issuing_certificates  = ["http://vault.vault.svc.cluster.local:8200/v1/pki/ca"]
      crl_distribution_urls = ["http://vault.vault.svc.cluster.local:8200/v1/pki/crl"]
    }
  }

  roles = {
    orders-service-server = {
      mount              = "pki"
      allowed_domains    = ["orders-service", "orders-service.orders", "orders-service.orders.svc", "orders-service.orders.svc.cluster.local"]
      allow_bare_domains = true
      allow_subdomains   = false
      server_flag        = true
      client_flag        = false
      key_type           = "rsa"
      key_bits           = 2048
      ttl                = "900"
      max_ttl            = "1800"
    }
    frontend-service-client = {
      mount              = "pki"
      allowed_domains    = ["frontend-service", "frontend-service.orders", "frontend-service.orders.svc", "frontend-service.orders.svc.cluster.local"]
      allow_bare_domains = true
      allow_subdomains   = false
      server_flag        = false
      client_flag        = true
      key_type           = "rsa"
      key_bits           = 2048
      ttl                = "900"
      max_ttl            = "1800"
    }
  }
}

kubernetes_auth = {
  enabled              = true
  backend_path         = "kubernetes"
  kubernetes_host      = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt = false

  workload_identities = {
    orders-service = {
      bound_service_account_names      = ["orders-service"]
      bound_service_account_namespaces = ["orders"]
      token_policies                   = ["orders-service-runtime"]
      token_ttl                        = 900
      token_max_ttl                    = 1800
      audience                         = "vault"
    }
    orders-service-vso = {
      bound_service_account_names      = ["orders-service-vso"]
      bound_service_account_namespaces = ["orders"]
      token_policies                   = ["orders-service-api-key-read", "orders-service-database-credentials-read", "orders-service-pki-server-issue", "frontend-service-pki-client-issue"]
      token_ttl                        = 600
      token_max_ttl                    = 1800
      audience                         = "vault"
    }
  }
}
