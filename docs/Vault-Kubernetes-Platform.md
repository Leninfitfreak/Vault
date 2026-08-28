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
- Final application-test Git revision before the documentation-only update: `fdb63bfaf8bb93ec4ca536677616a0ca2b4cfb29`.
- `orders-service-primary`: `Synced` and `Healthy`.
- `orders-service-recovery`: `Synced` and `Healthy`; recovery remained inactive as designed.
- Self-healing test: `frontend-service` was manually scaled to 2 replicas; Argo CD detected `OutOfSync` and restored the Git-desired 1 replica.
- Pruning test: a temporary `gitops-prune-verification` ConfigMap was added through the Helm chart and created by Argo CD, then removed from Git and automatically pruned by Argo CD.
- Application regression passed after GitOps ownership: `frontend-service` -> `orders-service`, `consumer-service` -> `orders-service`, `orders-service` -> PostgreSQL, and Traefik ingress HTTP 200.
- Existing Kubernetes Secrets remained present and Secret values were not displayed.

## Phase 3 Vault HA Raft Foundation

Phase 3 installs HashiCorp Vault as a GitOps-managed platform component without migrating application secrets.

Vault platform source:

- Wrapper chart: `platform/vault`
- Upstream chart: official HashiCorp `vault` Helm chart
- Chart version: `0.34.1`
- Vault image: `hashicorp/vault:2.0.4`
- Primary Argo CD Application: `vault-primary`
- Recovery Argo CD Application: `vault-recovery`
- AppProject: `platform`

Primary Vault runtime:

- Namespace: `vault`
- Replicas: 3
- Storage: integrated Raft
- PVCs: `data-vault-0`, `data-vault-1`, `data-vault-2`
- PVC size: 1Gi each
- PDB: `maxUnavailable: 1`
- UI service: internal `ClusterIP`
- Injector: disabled
- CSI: disabled
- Local TLS: disabled only for the Minikube lab

Production target:

- TLS enabled for API and cluster traffic
- Auto-unseal through a cloud KMS or HSM
- Root-token use replaced by a proper administrator authentication method and policies

### Approved Vault-Only Reset

Vault administrative access was lost during initial Phase 3 troubleshooting because a replacement root token was created as a child token and then revoked with its parent. The lesson is that Vault token hierarchy matters: revoking a parent token also revokes non-orphan child tokens. Phase 3 now preserves the newly generated root token only for remaining administrative verification and does not revoke it during this phase.

An approved Vault-only data reset was performed. The reset scope was limited to:

- Vault StatefulSet runtime
- Vault server pods
- Vault data PVCs `data-vault-0`, `data-vault-1`, and `data-vault-2`
- Vault initialization state

The reset did not affect:

- Argo CD
- `vault-primary` cluster
- `vault-dr` cluster
- `orders-service`
- PostgreSQL/application PVC `orders/data-postgresql-0`
- application Kubernetes Secrets
- Traefik
- non-Vault Argo CD Applications

Before deletion, the Vault StatefulSet was confirmed to use volume claim template `data`, and the pods mounted:

- `vault-0` -> `data-vault-0`
- `vault-1` -> `data-vault-1`
- `vault-2` -> `data-vault-2`

Only those three exact Vault PVC names were deleted. No broad PVC selector was used.

### Reinitialization And Unseal

Vault was reinitialized exactly once after the reset:

- Initialization: completed
- Key shares: 5
- Threshold: 3
- Initialization material location: outside the repository under the local user profile
- Initialization material committed to Git: no
- Root token committed to Git: no
- Unseal keys committed to Git: no

All three Vault pods were securely unsealed:

- `vault-0`: initialized, unsealed, Raft storage, HA enabled
- `vault-1`: initialized, unsealed, Raft storage, HA enabled
- `vault-2`: initialized, unsealed, Raft storage, HA enabled

### Raft Verification

`vault operator raft list-peers` was verified using the protected administrative token. Only non-sensitive peer metadata was recorded:

- `vault-0` at `vault-0.vault-internal:8201`: leader, voter
- `vault-1` at `vault-1.vault-internal:8201`: follower, voter
- `vault-2` at `vault-2.vault-internal:8201`: follower, voter

Expected HA/Raft model was met:

- Peers: 3
- Leaders: 1
- Followers: 2
- Voters: 3

### Persistence And HA Tests

Standby persistence test:

- Restarted standby: `vault-1`
- PVC before restart: `pvc-12ee12c1-4216-4304-8711-254f252fa3bd`
- PVC after restart: `pvc-12ee12c1-4216-4304-8711-254f252fa3bd`
- PVC retained: yes
- Shamir unseal after restart: required and completed
- Peer rejoined: yes

Leader resilience test:

- Restarted leader: `vault-0`
- A different peer became leader during disruption
- `vault-0` recovered and was securely unsealed
- Final peers: 3
- Final voters: 3
- Final observed leader after the full cluster restart/unseal check: `vault-0`

Because the local lab uses Shamir sealing, Vault pods require manual unseal after restarts. Production should use auto-unseal.

### Argo CD Self-Heal

Vault GitOps self-healing was verified with a metadata-only drift on the `vault` Service:

- Drift: changed managed metadata label `app.kubernetes.io/name` from `vault` to `vault-drift`
- Detection: `vault-primary` reported `OutOfSync` and `Healthy`
- Self-heal: Argo CD restored the label to `vault`
- Final state: `vault-primary` returned to `Synced` and `Healthy`

The self-heal test did not modify Vault PVCs, data, Secrets, initialization state, seal state, or Raft configuration.

### Recovery State

`vault-recovery` remains only a declarative recovery runtime definition:

- Argo CD sync: `Synced`
- Argo CD health: `Healthy`
- Primary data restored to recovery: no
- Snapshot restore implemented: no
- Failover implemented: no
- Independent recovery Vault initialized: no

### Application Regression After Vault

The existing application remained unaffected:

- `frontend-service` -> `orders-service`: HTTP 200
- `consumer-service` -> `orders-service`: HTTP 200
- `orders-service` -> PostgreSQL: HTTP 200 and TCP connectivity succeeded
- Traefik ingress using `orders.primary.local`: HTTP 200
- Application-reported secret source: `kubernetes-secret`

Application Kubernetes Secrets remained present:

- `external-service-credentials`: `Opaque`, 1 data key
- `orders-service-credentials`: `Opaque`, 3 data keys

Vault is not used by the application in Phase 3.

### Security Review

Confirmed:

- Vault initialization material is outside Git
- Vault root token is outside Git
- No Vault admin credentials are present in Helm values
- No Vault admin credentials are present in Argo CD resources
- No unseal keys are present in Git history
- No Vault root-token pattern was found in Git history
- No application Secret migration was performed
- No future-phase Vault features were configured

During verification, one metadata-intended command accidentally printed base64-encoded values from the existing fake local Kubernetes application Secrets to tool output. The values are the same fake local-only values already present in the Phase 1 chart defaults, and no secret values were added to documentation or committed as new material. Subsequent Secret checks used only name, type, and data-count output.

Deferred:

- Kubernetes Auth
- Vault policies
- KV secrets
- Terraform
- PKI
- database secrets
- Vault Agent
- Vault Secrets Operator
- CSI
- backups
- DR restore
- failover

## Phase 4 Reusable Multi-Environment Vault Configuration

Phase 4 makes the Vault platform reusable across environments and projects before any application onboarding begins. The goal is to keep Vault runtime logic common while environment-specific differences are expressed through values.

No Vault business capabilities were added in Phase 4. Kubernetes Auth, policies, KV secrets, application migration, Vault Agent, VSO, CSI, database secrets, PKI, Terraform, CI/CD, snapshots, restore, failover, failback, and MCP remain deferred.

### Repository Structure

Final Vault configuration structure:

```text
platform/
  vault/
    Chart.yaml
    Chart.lock
    environments.yaml
    values.yaml
    values/
      dev.yaml
      qa.yaml
      primary.yaml
      recovery.yaml
```

`values.yaml` contains common Vault defaults:

- official Vault image pin
- HA mode
- integrated Raft enablement
- shared health probes
- shared service behavior
- shared service account behavior
- shared PDB behavior
- shared local storage defaults
- shared local TLS-disabled behavior
- reusable non-secret platform metadata model

Environment files override only what differs:

- `dev.yaml`: development role, 1 Vault replica, smaller resources, local ClusterIP exposure
- `qa.yaml`: QA role, 3 Vault replicas, moderate resources, local ClusterIP exposure
- `primary.yaml`: production primary role, 3 Vault replicas, active primary runtime
- `recovery.yaml`: production recovery role, staged/inactive runtime definition

`environments.yaml` is a concise non-secret catalog for future automation:

- environment name
- role
- Vault values file
- intended destination
- deploy-by-default flag

It contains no credentials, kubeconfig data, Vault tokens, unseal keys, application secrets, or Argo credentials.

### Environment Model

The role model is generic:

- `development`: lower local resource footprint for development rendering or future dev clusters
- `qa`: production-like topology where practical
- `primary`: active production-style primary runtime
- `recovery`: recovery runtime definition without data restoration or failover logic

Recovery orchestration is intentionally not encoded in Helm values. The chart describes runtime shape; future restore and failover workflows belong to later phases.

### GitOps Mapping

Current explicit Applications remain the clearest model for two live environments:

```text
vault-primary
  -> platform/vault
  -> values/primary.yaml
  -> primary cluster

vault-recovery
  -> platform/vault
  -> values/recovery.yaml
  -> recovery cluster
```

Future environments can add explicit Applications such as `vault-dev` and `vault-qa` using the same chart path and their environment values files. ApplicationSet is deferred until the environment count justifies the extra abstraction.

Desired-state flow remains:

```text
Git environment values
       |
       v
Argo CD
       |
       v
Official HashiCorp Vault Helm chart
       |
       v
Kubernetes
```

Direct `helm install` or `helm upgrade` is not the normal operating path.

Phase 4 did not repeat the destructive-adjacent Vault drift test because the Argo CD Application ownership model, sync policy, and rendered primary Kubernetes resources were not changed by the reusable values refactor. The Phase 3 metadata-only self-heal test remains the current live acceptance evidence, and Phase 4 reverified `vault-primary` as `Synced` and `Healthy` after the pushed commit.

### TLS Model

Current local state:

- Vault server transport TLS remains disabled for the Minikube-only runtime.
- No certificates or private keys are committed.
- No Vault PKI engine is configured.

Reusable values model:

- `platform.tls.enabled`
- `platform.tls.secretName`
- `platform.tls.caSecretName`
- `platform.tls.serverName`

Production model:

- TLS must be enabled for Vault API and cluster traffic.
- Certificates must come from an approved certificate source.
- Private keys must remain outside Git.
- Auto-unseal should be backed by a cloud KMS or HSM.

### Storage Model

Common storage behavior:

- integrated Raft data stored at `/vault/data`
- configurable PVC size
- configurable storage class
- configurable access mode

Current local state:

- `storageClass: null` uses the cluster default storage class in Minikube.
- Primary uses three 1Gi PVCs.

Cloud portability:

- AKS, EKS, GKE, and OpenShift deployments should override storage class and sizing through environment values.
- Cloud production storage should use the platform-approved encrypted block storage class and appropriate backup/snapshot controls in a later phase.

### Resource Model

Common baseline:

- requests: `100m` CPU and `256Mi` memory
- limits: `500m` CPU and `512Mi` memory

Environment overrides:

- dev: smaller local footprint, 1 replica, `50m/128Mi` requests and `250m/256Mi` limits
- QA: 3 replicas, moderate local footprint, common baseline resources
- primary: 3 replicas, production-style topology using the common local baseline for this lab
- recovery: staged/inactive definition, no live Vault server pods

Local values are not production sizing recommendations. Production sizing must be based on workload, storage latency, audit logging, request rate, and platform SLOs.

### Service Exposure Model

Common exposure is internal-first:

- Vault services are `ClusterIP`
- UI service is internal `ClusterIP`
- public exposure defaults to false
- ingress defaults to disabled

No public Vault ingress was created in Phase 4.

### Project Reuse

The Vault runtime layer has no dependency on `orders-service`. It is defined under `platform/vault`, has its own `platform` AppProject, and can be reused by another application or project by changing environment values and GitOps destination mapping.

Application onboarding remains a future phase.

### Validation

Pre-phase state:

- Git branch: `main`
- Previous commit: `9082c18 Document Phase 3 Vault runtime acceptance`
- Argo CD Applications: `orders-service-primary`, `orders-service-recovery`, `vault-primary`, and `vault-recovery` were `Synced` and `Healthy`
- Vault primary: 3 pods running, initialized, unsealed, HA enabled, integrated Raft
- Raft peers: 3 voters, 1 leader, 2 followers

Helm validation:

- `helm lint platform/vault`: pass
- dev render: pass, 1 Vault replica, Raft enabled
- QA render: pass, 3 Vault replicas, Raft enabled
- primary render: pass, 3 Vault replicas, Raft enabled
- recovery render: pass, intentionally empty/inactive

Security validation:

- no root-token pattern in Vault values
- no unseal-key pattern in Vault values
- no encoded-token pattern in Vault values
- no application secret values in Vault values
- no private-key marker in Vault values
- no root-token, unseal-key, or encoded-token pattern found in Git history

### Portability Review

To deploy the same Vault platform to AKS, EKS, GKE, OpenShift, or another conformant Kubernetes platform, environment values should supply:

- storage class and capacity
- resource requests and limits
- node topology and scheduling constraints
- TLS certificate Secret names and server names
- auto-unseal provider configuration in a later phase
- internal load balancer or ingress policy if required
- cloud identity and workload identity integration in a later phase

Minikube-specific assumptions are isolated to local values and documentation:

- default storage class via `storageClass: null`
- small resource sizes
- TLS disabled for the local-only runtime
- no cloud KMS auto-unseal
- no public load balancer

### Problems And Lessons

Problem:
Helm was installed locally through Winget but was not available on PATH in the shell session.

Resolution:
The installed Helm binary was invoked directly from the Winget package path for render validation.

Lesson:
The reusable values model should be validated with rendering before GitOps reconciliation, especially around StatefulSet-backed systems like Vault where accidental pod-template or PVC changes can trigger operational work.

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
