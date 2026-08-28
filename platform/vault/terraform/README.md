# Vault Terraform Foundation

Terraform owns Vault logical configuration only. Argo CD and Helm continue to own the Kubernetes runtime that runs Vault.

```text
Git + Argo CD + Helm -> Kubernetes Vault runtime
Terraform            -> Vault logical configuration
```

Phase 5 proves Terraform ownership with one safe policy named `platform-readiness`. It grants read access to `sys/health` and contains no secret data.

Phase 6 adds Kubernetes Auth and workload identity authorization. The first workload role is `orders-service`, bound explicitly to ServiceAccount `orders-service` in namespace `orders`.

## Authentication

Local bootstrap uses externally supplied environment variables:

- `VAULT_ADDR`
- `VAULT_TOKEN`
- optional provider-supported TLS environment such as `VAULT_CACERT`

Do not place tokens, unseal keys, passwords, private keys, or application secrets in Terraform files, tfvars, documentation, shell scripts, or Kubernetes manifests.

Production should replace root-token bootstrap with a non-root automation identity that receives short-lived tokens through an approved Vault auth method and least-privilege policy.

Workload authentication uses Kubernetes TokenRequest JWTs:

```text
Pod ServiceAccount JWT
        |
        v
auth/kubernetes/login
        |
        v
Vault role
        |
        v
short-lived Vault token
```

The Phase 6 role uses:

- auth path: `kubernetes`
- Kubernetes API: `https://kubernetes.default.svc:443`
- reviewer model: Vault's in-pod ServiceAccount token and CA
- allowed ServiceAccount: `orders-service`
- allowed namespace: `orders`
- policy: `orders-service-runtime`
- token TTL: 900 seconds
- token max TTL: 1800 seconds
- audience: `vault`

The role does not attach `root` or administrator policies.

## State

Local state is acceptable for this phase and is ignored by Git. Terraform state and plan files must be treated as sensitive.

Production should use an encrypted remote backend with locking, access control, auditability, and backup/versioning, such as Terraform Cloud/Enterprise, S3 with locking, Azure Storage, or GCS.

## Environments

- `environments/dev`: static validation only
- `environments/qa`: static validation only
- `environments/primary`: live Phase 5 and Phase 6 apply target
- `environments/recovery`: staged only; no live recovery apply in Phase 5 or Phase 6

Recovery does not restore primary data, configure snapshots, or implement failover.

## Reuse

Additional workloads can be onboarded through configuration data rather than changing shared modules:

```hcl
workload_identities = {
  payment-service = {
    bound_service_account_names      = ["payment-service"]
    bound_service_account_namespaces = ["payments"]
    token_policies                   = ["payment-service-runtime"]
    token_ttl                        = 900
    token_max_ttl                    = 1800
    audience                         = "vault"
  }
}
```

Do not place application secret values in Terraform. Secret migration belongs to a later phase.
