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
      token_policies                   = ["orders-service-api-key-read", "orders-service-database-credentials-read"]
      token_ttl                        = 600
      token_max_ttl                    = 1800
      audience                         = "vault"
    }
  }
}
