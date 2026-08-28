# Reusable Kubernetes Application Foundation

This repository defines the Phase 1 state of an existing enterprise Kubernetes application before HashiCorp Vault onboarding.

Phase 2 adds Argo CD as the GitOps reconciler. Git is the desired-state source, Argo CD performs continuous reconciliation, and Helm remains the packaging/template mechanism for the application chart.

Phase 3 adds HashiCorp Vault as a GitOps-managed platform component. Vault is deployed from the official HashiCorp Helm chart through Argo CD, runs in HA mode with integrated Raft storage on the primary cluster, and keeps recovery as a declarative inactive definition only.

Minikube is used only for local validation of two Kubernetes environments:

- `vault-primary`: active primary environment
- `vault-dr`: recovery environment

The reusable application package is a Helm chart at `applications/orders-service`. It models a production-style service topology:

```text
ingress / Traefik
       |
       v
frontend-service
       |
       v
orders-service
  /          \
 v            v
K8s Secrets  PostgreSQL
 ^
 |
consumer-service
```

Phase 1 intentionally uses ordinary Kubernetes Secrets with fake local-only values. This simulates the starting point for later migration to Vault. Real production secrets must never be committed to Git.

## Helm Values Strategy

- `values.yaml`: common reusable defaults
- `values/primary.yaml`: active primary environment
- `values/recovery.yaml`: inactive recovery environment

The chart is designed so another project or cluster can change values rather than rewrite templates.

## GitOps Strategy

Argo CD is bootstrapped once into `vault-primary` as the local management cluster. The GitOps layer is under `gitops/argocd`:

- `bootstrap/`: one-time Argo CD installation
- `projects/`: restricted `orders` and `platform` AppProjects
- `applications/`: primary and recovery Argo CD Applications for the app and Vault platform runtime
- `cluster-registration/`: non-secret RBAC used to register `vault-dr`

Routine desired-state changes should be made in Git and reconciled by Argo CD. Direct Helm commands remain useful for linting and rendering, but are no longer the normal deployment path after Argo CD ownership is active.

Phase 2 verification completed with `origin/main` published and both Argo CD Applications reporting `Synced` and `Healthy`. Automated self-healing was verified by temporarily scaling `frontend-service` to 2 replicas and watching Argo CD restore the Git-desired count of 1. Automated pruning was verified with a temporary non-sensitive ConfigMap, which Argo CD created from Git and pruned after it was removed from Git.

## Vault Platform Runtime

Vault is defined at `platform/vault` as a wrapper chart around the official HashiCorp `vault` Helm chart.

- Helm chart: `hashicorp/vault`
- Chart version: `0.34.1`
- Vault image: `hashicorp/vault:2.0.4`
- Primary Argo CD Application: `vault-primary`
- Recovery Argo CD Application: `vault-recovery`
- Primary namespace: `vault`
- Primary replicas: 3
- Storage: integrated Raft with 1Gi persistent volume claim per Vault server
- Local seal model: Shamir, 5 key shares, threshold 3
- Local TLS: disabled for this Minikube-only phase
- Production target: TLS enabled and auto-unseal backed by a cloud KMS or HSM

Phase 3 verification completed after an approved Vault-only data reset. The reset affected only the Vault StatefulSet runtime, the `vault` namespace data PVCs `data-vault-0`, `data-vault-1`, and `data-vault-2`, and Vault initialization state. Argo CD, the clusters, orders-service, PostgreSQL PVCs, application Kubernetes Secrets, Traefik, and unrelated GitOps Applications were not reset.

Vault was reinitialized exactly once after the reset. Initialization material is stored outside the repository under the local user profile and is not committed to Git. The generated root token is preserved only for Phase 3 administrative verification and was not revoked during this phase. Future Vault configuration phases must replace root-token use with proper administrator authentication and policy boundaries before revoking the root token.

Runtime acceptance verified:

- `vault-primary`: `Synced` and `Healthy`
- `vault-recovery`: `Synced` and `Healthy`, inactive as designed
- Raft peers: `vault-0`, `vault-1`, and `vault-2`
- Final leader: `vault-0`
- Followers: `vault-1`, `vault-2`
- Voters: all three peers
- Standby persistence: `vault-1` restarted, retained its PVC, was securely unsealed, and rejoined
- Leader resilience: `vault-0` restarted, another peer became leader during disruption, `vault-0` recovered, and final peer count returned to 3
- Argo CD self-heal: a metadata-only drift on the Vault Service label was detected as `OutOfSync`; Argo restored the Git value and returned `vault-primary` to `Synced` and `Healthy`

Vault does not manage application secrets yet. The application still uses Kubernetes Secrets and reports `secret_source: kubernetes-secret`. Kubernetes Auth, policies, KV, PKI, database secrets, Vault Agent, VSO, CSI, backups, DR restore, and failover are intentionally deferred.

## Multi-Environment Vault Configuration

Phase 4 separates reusable Vault platform logic from environment-specific configuration:

```text
Vault platform definition
          |
  +-------+-------+----------------+
  |               |                |
 dev              qa           production
                              |
                         +----+----+
                         |         |
                      primary   recovery
```

The shared Vault defaults stay in `platform/vault/values.yaml`. Environment overrides live in `platform/vault/values/dev.yaml`, `values/qa.yaml`, `values/primary.yaml`, and `values/recovery.yaml`. The non-secret environment catalog at `platform/vault/environments.yaml` records names, roles, value files, and intended destinations for future automation.

The same chart remains independent of `orders-service`; application onboarding is deferred. Current local values keep Vault server TLS disabled only for Minikube validation, while the documented production model requires TLS and auto-unseal through an external KMS or HSM.

## Vault Configuration As Code

Phase 5 introduces Terraform for Vault logical configuration while keeping Argo CD and Helm responsible for Kubernetes runtime reconciliation.

```text
                        Git
                         |
             +-----------+-----------+
             |                       |
             v                       v
          Argo CD                 Terraform
             |                       |
             v                       v
            Helm             Vault logical config
             |                       |
             v                       |
        Kubernetes                   |
             |                       |
             +---------> Vault <-----+
                         |
                    Integrated Raft
```

Terraform configuration lives under `platform/vault/terraform`. The first live proof resource is a harmless Vault policy named `platform-readiness`, which grants only read access to `sys/health` and contains no secret data.

Terraform local bootstrap authentication uses externally supplied `VAULT_ADDR` and `VAULT_TOKEN` values. Tokens, unseal keys, Terraform state, plan files, and local environment files are excluded from Git. The provider lock file is committed for deterministic provider selection.

## Vault Kubernetes Auth

Phase 6 enables Vault Kubernetes Auth through Terraform so workloads can authenticate with Kubernetes ServiceAccount identity instead of static Vault tokens.

```text
                       Git
                        |
          +-------------+-------------+
          |                           |
          v                           v
       Argo CD                     Terraform
          |                           |
          v                           v
    Kubernetes                   Vault Config
          |                           |
          |                    Kubernetes Auth
          |                           |
          v                           v
     Application --------------->   Vault
          |      SA identity         |
          |                          |
          +---- existing K8s --------+
                Secrets still used
                during Phase 6
```

The initial workload role is `orders-service`, bound only to ServiceAccount `orders-service` in namespace `orders`. It receives a short-lived Vault token with only the `orders-service-runtime` policy. That policy permits only read access to `sys/health` for authorization proof; no application secrets were migrated to Vault.

## Included In Phase 1

- Helm chart for `frontend-service`, `orders-service`, `consumer-service`, and `postgresql`
- Static Kubernetes Secrets using fake local-only values
- Primary runtime deployment, now prepared for Argo CD reconciliation
- Recovery values and environment metadata
- Documentation for the before-Vault architecture

## Excluded From Phase 1

- HashiCorp Vault
- Argo CD
- Terraform
- CI/CD
- Vault Agent, VSO, CSI
- PKI and mTLS
- Dynamic database credentials
- Backup, restore, and DR automation
- MCP and production agent access controls

## Production Agent Access Control - Deferred

MCP is intentionally not part of the current local Phase 1 lab. Current Codex usage is limited to the local development environment.

Production credentials must never be exposed to the development agent environment. Production administration is expected to use a separately controlled environment or device. If agent-based production inspection is introduced later, it must use dedicated least-privilege identities and an appropriate isolation/control layer. Production write operations should remain human-controlled unless a separately approved security design is introduced.
