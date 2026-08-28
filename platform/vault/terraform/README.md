# Vault Terraform Foundation

Terraform owns Vault logical configuration only. Argo CD and Helm continue to own the Kubernetes runtime that runs Vault.

```text
Git + Argo CD + Helm -> Kubernetes Vault runtime
Terraform            -> Vault logical configuration
```

Phase 5 proves Terraform ownership with one safe policy named `platform-readiness`. It grants read access to `sys/health` and contains no secret data.

## Authentication

Local bootstrap uses externally supplied environment variables:

- `VAULT_ADDR`
- `VAULT_TOKEN`
- optional provider-supported TLS environment such as `VAULT_CACERT`

Do not place tokens, unseal keys, passwords, private keys, or application secrets in Terraform files, tfvars, documentation, shell scripts, or Kubernetes manifests.

Production should replace root-token bootstrap with a non-root automation identity that receives short-lived tokens through an approved Vault auth method and least-privilege policy.

## State

Local state is acceptable for this phase and is ignored by Git. Terraform state and plan files must be treated as sensitive.

Production should use an encrypted remote backend with locking, access control, auditability, and backup/versioning, such as Terraform Cloud/Enterprise, S3 with locking, Azure Storage, or GCS.

## Environments

- `environments/dev`: static validation only
- `environments/qa`: static validation only
- `environments/primary`: live Phase 5 apply target
- `environments/recovery`: staged only; no live recovery apply in Phase 5

Recovery does not restore primary data, configure snapshots, or implement failover.
