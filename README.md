# Reusable Kubernetes Application Foundation

This repository defines the Phase 1 state of an existing enterprise Kubernetes application before HashiCorp Vault onboarding.

Phase 2 adds Argo CD as the GitOps reconciler. Git is the desired-state source, Argo CD performs continuous reconciliation, and Helm remains the packaging/template mechanism for the application chart.

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
- `projects/`: restricted `orders` AppProject
- `applications/`: primary and recovery Argo CD Applications
- `cluster-registration/`: non-secret RBAC used to register `vault-dr`

Routine desired-state changes should be made in Git and reconciled by Argo CD. Direct Helm commands remain useful for linting and rendering, but are no longer the normal deployment path after Argo CD ownership is active.

Phase 2 verification completed with `origin/main` published and both Argo CD Applications reporting `Synced` and `Healthy`. Automated self-healing was verified by temporarily scaling `frontend-service` to 2 replicas and watching Argo CD restore the Git-desired count of 1. Automated pruning was verified with a temporary non-sensitive ConfigMap, which Argo CD created from Git and pruned after it was removed from Git.

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
