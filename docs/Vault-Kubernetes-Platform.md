# Vault Kubernetes Platform

## Phase 1 Objective

Phase 1 establishes the before-Vault state for a reusable enterprise Kubernetes application foundation. Minikube is used only as a local substitute for real Kubernetes clusters such as AKS, EKS, GKE, OpenShift, or another conformant Kubernetes platform.

Phase 2 adds Argo CD as the GitOps reconciler. This project still does not install Vault, Terraform, CI/CD, PKI, VSO, CSI, Vault Agent, dynamic database credentials, backup, restore, failover automation, MCP, or production agent access controls.

## Current Architecture

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

`orders-service` is the primary future Vault consumer. It currently reads an API credential and static PostgreSQL username/password from Kubernetes Secrets.

## Environment Architecture

- `vault-primary`: active primary environment with application workloads deployed.
- `vault-dr`: recovery environment with the Helm release installed and `global.active=false`; no workload pods are deployed.

Both Minikube profiles are healthy and use Kubernetes `v1.35.1` with the Docker driver.

## Existing Credential Model

Phase 1 intentionally uses ordinary Kubernetes Secrets:

- `orders-service-credentials`
  - `API_KEY`
  - `DB_USERNAME`
  - `DB_PASSWORD`
- `external-service-credentials`
  - `EXTERNAL_API_TOKEN`

All values are fake local-only values. Real production secret values must never be committed to Git.

## Helm Model

The application is packaged as a reusable Helm chart:

```text
applications/orders-service
  Chart.yaml
  values.yaml
  values/
    primary.yaml
    recovery.yaml
  templates/
```

Common behavior lives in `values.yaml`. Environment-specific behavior is controlled by `values/primary.yaml` and `values/recovery.yaml`.

## Runtime State

Primary release:

- Release: `orders-service`
- Context: `vault-primary`
- Status: managed by Argo CD
- Argo CD Application: `orders-service-primary`
- Sync: `Synced`
- Health: `Healthy`

Recovery release:

- Release: `orders-service`
- Context: `vault-dr`
- Status: managed by Argo CD
- Argo CD Application: `orders-service-recovery`
- Sync: `Synced`
- Health: `Healthy`
- Workloads: inactive, no pods

Primary workload status:

- `frontend-service`: running and rolled out
- `orders-service`: running and rolled out
- `consumer-service`: running and rolled out
- `postgresql`: running and rolled out
- `traefik`: running and rolled out

Connectivity verified:

- `frontend-service` -> `orders-service`: succeeded
- `consumer-service` -> `orders-service`: succeeded
- `orders-service` -> `PostgreSQL`: succeeded
- Traefik ingress for `orders.primary.local`: succeeded

Secret consumption was verified without printing values:

- `orders-service` references `orders-service-credentials/API_KEY`
- `orders-service` references `orders-service-credentials/DB_USERNAME`
- `orders-service` references `orders-service-credentials/DB_PASSWORD`
- `postgresql` references `orders-service-credentials/DB_USERNAME`
- `postgresql` references `orders-service-credentials/DB_PASSWORD`

No Vault or Argo CD Helm releases or namespaces were found.

## Tool Versions

- Git: `2.53.0.windows.2`
- Docker: client/server `29.7.2`
- Minikube: `v1.38.1`
- kubectl client: `v1.36.1`
- Helm: `v4.1.3`

Kubeconfig was readable with elevated local access. Existing unrelated contexts were preserved.

## Cluster Versions

- `vault-primary`: Kubernetes `v1.35.1`, Docker driver, healthy
- `vault-dr`: Kubernetes `v1.35.1`, Docker driver, healthy

## Security Considerations

Implemented:

- non-root application containers
- read-only root filesystem for Python services and Traefik
- dropped capabilities for Python services and Traefik
- privilege escalation disabled
- dedicated ServiceAccounts per component
- resource requests and limits
- readiness and liveness probes
- internal-only PostgreSQL service
- read-only RBAC for Traefik ingress discovery
- fake local-only Kubernetes Secrets

Known limitation:

- PostgreSQL uses a less restrictive container security context because the official image entrypoint requires permission changes at startup.

## Portability

Reusable:

- Helm templates
- values-driven naming
- namespace configuration
- component configuration
- resource requests and limits
- Secret structure
- stable service names for future service identity

Environment-specific:

- `values/primary.yaml`
- `values/recovery.yaml`
- ingress host
- active/inactive mode
- storage size

Minikube-specific:

- local `vault-primary` and `vault-dr` profiles
- Docker driver
- NodePort exposure for local Traefik validation

The reusable chart does not hardcode Minikube IPs, local host paths, user-specific paths, Windows paths, or kubeconfig context names.

## Future mTLS Readiness

The current service topology preserves a stable future path:

```text
consumer-service
      |
      | future mTLS
      v
orders-service
```

Stable service DNS names for future certificate SANs:

- `orders-service.orders.svc`
- `orders-service.orders.svc.cluster.local`

No TLS, PKI, certificate issuance, or Vault integration is implemented in Phase 1.

## Cleanup Performed

Obsolete live Kubernetes resources from an abandoned Kustomize implementation were removed earlier:

- `demo` namespace from `vault-primary`
- `demo` namespace from `vault-dr`
- old `traefik` IngressClass from `vault-primary`
- old `demo-traefik-ingress-controller` ClusterRole and ClusterRoleBinding from `vault-primary`

Obsolete MCP repository and cluster resources were removed after MCP was deferred:

- `.vscode/mcp.json`
- `control-plane/mcp/`
- `mcp-system` namespace from `vault-primary`
- `mcp-system` namespace from `vault-dr`
- `mcp-readonly` ClusterRole and ClusterRoleBinding from both clusters

No unrelated kubeconfig contexts, clusters, Helm releases, or user resources were deleted.

## Problems and Troubleshooting

Problem:
PostgreSQL initially failed with permission errors when the first template dropped all Linux capabilities.

Resolution:
The PostgreSQL container security context was relaxed by removing `capabilities.drop: ALL` only for PostgreSQL. Other application containers keep the stricter non-root, read-only filesystem, no privilege escalation, and dropped-capabilities baseline.

Problem:
Traefik initially returned HTTP 404 for the primary Ingress after the app was otherwise healthy.

Resolution:
The Traefik Helm template now creates the `traefik` IngressClass and grants only the read-only discovery permissions Traefik needs for EndpointSlices, nodes, and IngressClasses. The Traefik deployment was restarted after the RBAC update and ingress validation returned HTTP 200.

## Future Phase Boundaries

Current GitOps model:

```text
Git
 |
 v
Argo CD
 |
 v
Helm
 |
 v
Kubernetes
```

Argo CD is bootstrapped once into `vault-primary` as the local management cluster. After bootstrap, routine desired-state changes flow through Git and are reconciled by Argo CD. Helm remains the packaging and template mechanism; Argo CD is the continuous reconciler.

Argo CD installation:

- Namespace: `argocd`
- Bootstrap path: `gitops/argocd/bootstrap`
- Installation source: official Argo CD stable install manifest
- Local UI/API access: use temporary port-forwarding to `svc/argocd-server`; no permanent external exposure is configured.

Cluster management:

- `primary` -> `vault-primary` through in-cluster Argo CD access
- `recovery` -> `vault-dr` through a live Argo CD cluster registration named `vault-dr`
- unrelated kubeconfig contexts are not registered with Argo CD

AppProject:

- Name: `orders`
- Source repository restricted to `https://github.com/Leninfitfreak/Vault.git`
- Destinations restricted to the `orders` namespace on the primary in-cluster target and the registered `vault-dr` target
- Resource allow lists restrict the application to the Kubernetes kinds used by the current Helm chart

Application model:

- `orders-service-primary` uses `applications/orders-service` with `values/primary.yaml`
- `orders-service-recovery` uses `applications/orders-service` with `values/recovery.yaml`
- ApplicationSet is deferred because two explicit Applications are clearer for this two-environment foundation

Sync policy:

- Primary and recovery Applications are configured for automated sync, self-healing, and pruning
- Safe pruning is intended for resources managed by the Argo CD Application
- PVCs, Secrets, database state, and production-style destructive changes require care and should not be used for drift tests

Ownership transition:

- Phase 1 was deployed directly with Helm.
- Phase 2 preserves the Helm release identity `orders-service` so Argo CD renders the same chart and values instead of creating a duplicate application.
- Argo CD is configured to use `argocd.argoproj.io/instance` for resource tracking so it does not rewrite Helm selector labels based on `app.kubernetes.io/instance`.
- Full Application sync, self-healing, and pruning require the current repository contents to be committed and pushed to the configured Git source.

GitOps drift model:

```text
manual kubectl/Helm change
        |
        v
       drift
        |
        v
     Argo CD
        |
        v
reconcile back to Git
```

Why GitOps comes before Vault:

- Vault onboarding will add sensitive platform state, authentication, policies, and secret-delivery resources.
- Argo CD provides a controlled reconciliation path before those future security components are introduced.
- This keeps later Vault changes reviewable as Git changes rather than ad hoc cluster mutations.

Phase 2 verification results:

- `origin/main` was published successfully to `https://github.com/Leninfitfreak/Vault.git`.
- Final verified Git revision: `fdb63bfaf8bb93ec4ca536677616a0ca2b4cfb29`.
- `orders-service-primary`: `Synced` and `Healthy`.
- `orders-service-recovery`: `Synced` and `Healthy`; recovery remained inactive as designed.
- Self-healing test: `frontend-service` was manually scaled to 2 replicas; Argo CD detected `OutOfSync` and restored the Git-desired 1 replica.
- Pruning test: a temporary `gitops-prune-verification` ConfigMap was added through the Helm chart and created by Argo CD, then removed from Git and automatically pruned by Argo CD.
- Application regression passed after GitOps ownership: `frontend-service` -> `orders-service`, `consumer-service` -> `orders-service`, `orders-service` -> PostgreSQL, and Traefik ingress HTTP 200.
- Existing Kubernetes Secrets remained present and Secret values were not displayed.

Future Vault migration model:

```text
Kubernetes Secrets
       |
       v
HashiCorp Vault
```

Planned future mapping:

- API key -> Vault KV
- static PostgreSQL credentials -> Vault Database Secrets Engine
- internal TLS certificates -> Vault PKI
- application authentication -> Kubernetes Auth
- Kubernetes Secret consumption -> Vault Agent, VSO, or CSI depending on use case

Phase 2 must not start until explicitly approved.

## Production Agent Access Control - Deferred

MCP, agent isolation, production Kubernetes access control, AWS agent access, and production credential management are intentionally not part of the current local Phase 1 lab.

Current Codex usage is limited to the local development environment. Production credentials must never be exposed to the development agent environment, and production administration is expected to use a separately controlled environment or device.

If agent-based production inspection is introduced later, it must use dedicated least-privilege identities and an appropriate isolation/control layer. Production write operations should remain human-controlled unless a separately approved security design is introduced.

No replacement MCP solution, VS Code MCP setup, Docker MCP Gateway, ToolHive setup, Dev Container isolation, or production credential control is implemented in Phase 1.
