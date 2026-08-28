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

## Phase 5 Vault Configuration As Code With Terraform

Phase 5 introduces Terraform as the declarative owner for approved Vault logical configuration. It does not change the Kubernetes runtime ownership model.

Ownership boundary:

```text
Git + Argo CD + Helm
        |
        v
Kubernetes runtime infrastructure
        |
        v
Vault StatefulSet, Services, PVCs, ConfigMaps, RBAC

Terraform
        |
        v
Vault logical configuration
```

Terraform must not manage the Vault Helm release, Vault StatefulSet, Kubernetes Services, PVCs, Argo CD Applications, or `orders-service` Kubernetes resources.

### Terraform Structure

Final Terraform structure:

```text
platform/vault/terraform/
  README.md
  modules/
    policies/
      main.tf
      outputs.tf
      variables.tf
  environments/
    dev/
      main.tf
      outputs.tf
      providers.tf
      terraform.tfvars
      versions.tf
      variables.tf
    qa/
      main.tf
      outputs.tf
      providers.tf
      terraform.tfvars
      versions.tf
      variables.tf
    primary/
      .terraform.lock.hcl
      main.tf
      outputs.tf
      providers.tf
      terraform.tfvars
      versions.tf
      variables.tf
    recovery/
      main.tf
      outputs.tf
      providers.tf
      terraform.tfvars
      versions.tf
      variables.tf
```

The only populated shared module is `modules/policies`, because Phase 5 needed one real, low-risk proof resource. Namespaces were not implemented because Vault OSS does not support Vault namespaces. Auth and mounts modules are deferred until a later approved phase introduces those capabilities.

### Versioning

Validation used:

- Terraform CLI: `v1.14.8`
- Required Terraform version: `>= 1.14.0, < 2.0.0`
- Vault provider source: `hashicorp/vault`
- Vault provider version: `= 5.11.0`

`.terraform.lock.hcl` is committed for each environment root to keep provider selection deterministic. `.terraform/`, state files, and plan files are ignored.

### Authentication Model

Local bootstrap:

```text
protected local root/admin token
        |
        v
VAULT_TOKEN environment variable
        |
        v
Terraform provider
```

The token is not committed, echoed, printed, placed in tfvars, stored in scripts, or stored in Kubernetes manifests. The Phase 3 root token remains a bootstrap/emergency credential and was not revoked in Phase 5.

Production target:

```text
CI/CD or operator workload identity
        |
        v
Vault auth method
        |
        v
short-lived token
        |
        v
least-privilege Terraform policy
```

That production identity model is documented but not implemented in Phase 5.

### State Security

Local state was used for the primary environment in Phase 5. Terraform state and plan files are treated as sensitive and are excluded from Git.

Production must use an encrypted remote backend with locking, access control, auditability, and backup/versioning. Suitable future backend families include Terraform Cloud/Enterprise, S3 with locking, Azure Storage, or GCS.

Targeted state inspection after apply found no:

- Vault root-token pattern
- unseal-key pattern
- encoded-token pattern
- application password markers
- application API token markers
- private-key marker

### Environment Model

Environment behavior:

- `dev`: static validation only, no live apply
- `qa`: static validation only, no live apply
- `primary`: only live Phase 5 target
- `recovery`: staged only, no live apply

Recovery Terraform configuration exists for structure and future automation, but Phase 5 did not apply logical configuration to a recovery Vault instance.

### Phase 5 Proof Resource

Terraform manages one safe Vault logical resource:

- Type: `vault_policy`
- Name: `platform-readiness`
- Purpose: prove Terraform can own harmless Vault logical configuration
- Policy: read-only access to `sys/health`
- Secret data: none

No KV engine, database secrets engine, PKI, Kubernetes Auth, application policy, or application secret was created.

### Terraform Workflow Results

Primary workflow:

- `terraform fmt -check`: pass
- `terraform init`: pass
- `terraform validate`: pass
- `terraform providers`: `registry.terraform.io/hashicorp/vault` version `5.11.0`
- Initial plan: 1 resource to add, `platform-readiness`
- Apply: pass
- Second plan: no changes

Dev, QA, and recovery static validation:

- `terraform init -backend=false`: pass
- `terraform validate`: pass

Drift test:

- Object changed outside Terraform: `platform-readiness`
- Manual drift: added a non-secret extra capability to the same harmless policy
- Drift detected: yes, Terraform plan returned detailed exit code `2`
- Restore: Terraform applied the saved restore plan
- Final plan: no changes, detailed exit code `0`

### Existing Logical Configuration

Existing Vault policy names observed:

- `default`
- `default-ceiling`
- `platform-readiness`
- `root`

Terraform-owned object:

- `platform-readiness`

Manual operational state not managed by Terraform:

- Vault initialization
- Shamir unseal keys
- root token
- Raft peers and leadership
- Kubernetes runtime resources

### Runtime Regression

Vault primary after Terraform:

- Argo CD sync: `Synced`
- Argo CD health: `Healthy`
- Replicas: 3
- Pods: running
- Unsealed: yes
- HA: enabled
- Raft peers: 3
- Leader: `vault-0`
- Followers: `vault-1`, `vault-2`
- Reinitialized: no

Vault recovery:

- Argo CD sync: `Synced`
- Argo CD health: `Healthy`
- State: staged/inactive
- Terraform applied live: no
- Primary data restored: no

Application regression after Terraform:

- `frontend-service` -> `orders-service`: HTTP 200
- `consumer-service` -> `orders-service`: HTTP 200
- `orders-service` -> PostgreSQL: HTTP 200 and TCP connectivity succeeded
- Traefik ingress with `orders.primary.local`: HTTP 200
- Application-reported secret source: `kubernetes-secret`

Application Kubernetes Secrets remained present by metadata:

- `external-service-credentials`: `Opaque`, 1 data key
- `orders-service-credentials`: `Opaque`, 3 data keys

### Security Review

Confirmed:

- root token in Git: no
- unseal keys in Git: no
- Terraform state in Git: no
- application secrets in Terraform: no
- private keys in Git: no
- sensitive outputs: no
- sensitive values printed in Phase 5: no

Phase 5 `.gitignore` additions:

- `.terraform/`
- `*.tfstate`
- `*.tfstate.*`
- `*.tfplan`
- `.env`
- `.env.*`
- `*.secret`
- `*.credentials`

### Future Project Input Model

Later phases can add data-driven application onboarding without changing shared module internals. A future input model may look like:

```hcl
applications = {
  payment_service = {
    namespace       = "payments"
    service_account = "payment-service"
  }
}
```

This concept is documented only. No application auth role, policy, KV secret, or secret migration was implemented.

### Problems And Lessons

Problem:
The Terraform provider download initially failed under the restricted network sandbox.

Root cause:
Terraform needed network access to query `registry.terraform.io` and install the pinned provider.

Resolution:
Terraform init was rerun with approved network access and installed `hashicorp/vault v5.11.0`.

Problem:
Terraform `plan -out=phase5.tfplan` was rejected by the local CLI invocation, while `plan -out phase5.tfplan` worked.

Resolution:
The space-separated `-out phase5.tfplan` form was used for saved plans.

Lesson:
Terraform is now cleanly separated from Kubernetes runtime reconciliation. Argo CD owns Vault runtime state; Terraform owns only explicitly approved Vault logical objects.

## Phase 6 Vault Kubernetes Auth And Workload Identity

Phase 6 enables Vault Kubernetes Auth and establishes reusable workload identity authorization. It proves that Kubernetes workloads can authenticate to Vault with ServiceAccount identity and receive short-lived, least-privilege Vault tokens.

No application secret values were migrated. The application still consumes existing Kubernetes Secrets.

### Authentication Flow

```text
Kubernetes Pod
      |
      | ServiceAccount JWT
      v
Vault Kubernetes Auth
      |
      v
Vault Role
      |
      v
Vault Policy
      |
      v
short-lived Vault token
```

Authentication and authorization are separated:

- Kubernetes Auth proves workload identity.
- Vault role maps that identity to policies and token settings.
- Vault policy controls allowed access.

### Ownership Boundary

Argo CD and Helm continue to own Kubernetes runtime resources:

- Vault StatefulSet
- Vault Services
- Vault PVCs
- Vault ServiceAccount
- TokenReview RBAC
- application Kubernetes workloads

Terraform owns Vault logical configuration:

- Kubernetes auth backend
- Kubernetes auth backend configuration
- Kubernetes auth roles
- Vault policies

Terraform does not manage Kubernetes resources.

### Kubernetes ServiceAccounts

Actual workload identities inspected before implementation:

- `frontend-service` Deployment -> ServiceAccount `frontend-service`
- `orders-service` Deployment -> ServiceAccount `orders-service`
- `consumer-service` Deployment -> ServiceAccount `consumer-service`
- `postgresql` StatefulSet -> ServiceAccount `postgresql`

`orders-service` was selected as the Phase 6 proof workload because it is the future consumer of API and database credentials.

### TokenReview RBAC

The official Vault Helm chart already created the required minimal TokenReview binding:

- ServiceAccount: `vault` in namespace `vault`
- ClusterRoleBinding: `vault-server-binding`
- ClusterRole: `system:auth-delegator`
- Purpose: allow Vault Kubernetes Auth to validate ServiceAccount JWTs through the Kubernetes TokenReview API

No `cluster-admin`, `admin`, or `edit` role was granted.

### Terraform Resources

Phase 6 added a generic reusable module:

```text
platform/vault/terraform/modules/kubernetes-auth/
  main.tf
  outputs.tf
  variables.tf
```

Terraform-managed logical resources:

- `vault_auth_backend.kubernetes`
- `vault_kubernetes_auth_backend_config.this`
- `vault_kubernetes_auth_backend_role.workloads["orders-service"]`
- `vault_policy.this["orders-service-runtime"]`

The shared module contains no `orders-service` hardcoding. The workload-specific binding lives in `environments/primary/terraform.tfvars`.

### Kubernetes Auth Configuration

Configured values:

- Path: `auth/kubernetes`
- Kubernetes API: `https://kubernetes.default.svc:443`
- Reviewer model: Vault in-pod ServiceAccount token and local CA
- Long-lived reviewer JWT in Git: no
- `disable_local_ca_jwt`: false
- `token_reviewer_jwt_set`: false

This follows the supported in-cluster Vault model where Vault can use its own local ServiceAccount token and CA when running as a Kubernetes pod.

### Workload Role

Role: `orders-service`

- Bound ServiceAccount: `orders-service`
- Bound namespace: `orders`
- Audience: `vault`
- Token policy: `orders-service-runtime`
- Token TTL: 900 seconds
- Token max TTL: 1800 seconds
- Token type: default

The issued workload token includes Vault's unavoidable `default` policy and the explicit `orders-service-runtime` policy. It does not include `root`.

### Least-Privilege Policy

Policy: `orders-service-runtime`

Purpose:

- prove workload authorization without introducing application secret storage
- allow one harmless read operation against Vault health

Allowed path:

```hcl
path "sys/health" {
  capabilities = ["read"]
}
```

No `sys/*`, `auth/*`, `sudo`, root-like, KV, database, PKI, or application-secret permissions were granted.

### Validation Results

Terraform:

- Terraform version: `v1.14.8`
- Vault provider: `hashicorp/vault v5.11.0`
- `terraform fmt -check`: pass
- `terraform validate`: pass
- Initial Phase 6 plan: 4 resources to add, 0 change, 0 destroy
- Apply: pass
- Second plan: no changes
- Final idempotency: pass

Authentication tests:

- Correct ServiceAccount `orders/orders-service`: pass
- Wrong ServiceAccount `orders/frontend-service`: denied
- Wrong namespace `default/default`: denied

Authorization tests:

- Allowed operation `sys/health`: pass
- Unauthorized policy list: denied
- Administrative token creation: denied
- Root policy attached: no

Token metadata:

- Policies: `default`, `orders-service-runtime`
- TTL: 900 seconds
- TTL within expected range: yes
- Renewable: yes
- JWT printed: no
- Vault workload token printed: no

Token lifecycle:

```text
ServiceAccount JWT
      |
      v
Vault login
      |
      v
short-lived Vault token
      |
      v
expires or is revoked
      |
      v
workload authenticates again
```

Future Agent, VSO, or CSI integration can handle token renewal and reauthentication. Phase 6 did not introduce any of those components.

### Terraform Drift Test

Drift target:

- `orders-service-runtime` policy

Manual drift:

- temporarily added a non-secret extra capability to `sys/health`

Result:

- Terraform plan detected drift with detailed exit code `2`
- Terraform restored the declared policy
- Final plan returned no changes with exit code `0`

### State Security

Targeted primary state inspection found no:

- root-token pattern
- unseal-key pattern
- encoded-token pattern
- application password marker
- application API token marker
- private-key marker

A JWT-shaped pattern was found only in Terraform's opaque provider `private` metadata field, not in a named JWT/token attribute. No ServiceAccount JWT or Vault workload token was intentionally stored in Terraform state.

State files and plan files remain ignored by Git.

### Runtime Regression

Vault primary:

- Argo CD sync: `Synced`
- Argo CD health: `Healthy`
- Replicas: 3
- Pods: running
- Unsealed: yes
- HA: enabled
- Raft peers: 3
- Leader: `vault-0`
- Followers: `vault-1`, `vault-2`
- Reinitialized: no

Vault recovery:

- Argo CD sync: `Synced`
- Argo CD health: `Healthy`
- State: staged/inactive
- Terraform applied live: no
- Primary data restored: no

Application regression:

- `frontend-service` -> `orders-service`: HTTP 200
- `consumer-service` -> `orders-service`: HTTP 200
- `orders-service` -> PostgreSQL: HTTP 200 and TCP connectivity succeeded
- Traefik ingress with `orders.primary.local`: HTTP 200
- Existing Kubernetes Secrets preserved by metadata
- Application consuming Vault secrets: no

### Reuse Model

A future project can add workload identity through data:

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

No shared module changes should be required for another project with the same pattern.

### Cloud Portability

The Kubernetes Auth concept remains portable across EKS, AKS, GKE, OpenShift, and conformant Kubernetes distributions. Environment-specific configuration may need:

- Kubernetes API endpoint changes
- CA trust configuration
- network reachability from Vault to the Kubernetes API
- TokenReview RBAC review
- ServiceAccount token audience/issuer behavior validation
- cloud identity integration in a later phase

No cloud-specific integration was implemented in Phase 6.

### Security And Scope

Confirmed:

- root token in Git: no
- unseal keys in Git: no
- JWT in Git: no
- Vault workload token in Git: no
- Terraform state in Git: no
- application secrets in Terraform: no
- private keys in Git: no
- sensitive values exposed in Phase 6: no

Not implemented:

- KV application secret migration
- Vault Agent
- Vault Secrets Operator
- CSI
- dynamic database credentials
- database secrets engine
- PKI
- mTLS
- CI/CD
- snapshots
- restore
- failover
- MCP
- custom operator or CRD

### Problems And Lessons

Problem:
The Vault Terraform provider expects `token_ttl` and `token_max_ttl` on `vault_kubernetes_auth_backend_role` as numeric seconds, not duration strings.

Root cause:
The initial role input used human-readable strings such as `15m` and `30m`.

Resolution:
The module input schema and primary values were updated to use `900` and `1800`.

Lesson:
Auth resources should be planned before apply and checked against provider schema. The failed plan caught the type mismatch before any live Vault change was made.

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

## Phase 7 Vault KV And VSO Checkpoint

Phase 7 will migrate only the `orders-service` `API_KEY` from a manually managed Kubernetes Secret to Vault KV v2 delivered back to Kubernetes through the official HashiCorp Vault Secrets Operator.

The migration is intentionally narrow:

- selected workload: `orders-service`
- selected key: `API_KEY`
- keys not migrated: `DB_USERNAME`, `DB_PASSWORD`
- reason: database credentials are shared with PostgreSQL and are reserved for the later dynamic database credentials phase

Secret values were not printed during the checkpoint inspection.

### Current Secret Model

`orders-service` consumes `orders-service-credentials` through environment variables:

- `API_KEY`
- `DB_USERNAME`
- `DB_PASSWORD`

`postgresql` also consumes `DB_USERNAME` and `DB_PASSWORD` from `orders-service-credentials`.

The Phase 7 cutover must avoid two controllers owning the same Kubernetes Secret. The expected safe pattern is:

```text
Vault KV v2
    |
    v
Vault Secrets Operator
    |
    v
new VSO-managed Kubernetes Secret
    |
    v
orders-service API_KEY reference
```

The legacy `orders-service-credentials` Secret remains responsible for database credentials until the database secrets phase.

### Local Unseal Model

Local Minikube keeps the existing Vault seal model:

- seal: Shamir
- shares: 5
- threshold: 3
- initialization: existing initialization retained
- Raft data: existing PVC-backed Raft data retained

The helper at `scripts/local/vault-unseal.ps1` is a local-development-only convenience wrapper. It discovers Vault pods, skips already-unsealed pods, prompts for or reads three externally supplied Shamir shares, and submits shares without printing them.

The helper does not:

- hard-code Shamir shares
- persist Shamir shares
- print key values or prefixes
- initialize Vault
- reinitialize Vault
- delete PVCs
- change seal configuration
- change Raft membership

Example local usage with placeholders:

```powershell
$env:VAULT_UNSEAL_KEY_1 = "<share-1>"
$env:VAULT_UNSEAL_KEY_2 = "<share-2>"
$env:VAULT_UNSEAL_KEY_3 = "<share-3>"
.\scripts\local\vault-unseal.ps1
```

Clear the current session after use:

```powershell
Remove-Item Env:VAULT_UNSEAL_KEY_1 -ErrorAction SilentlyContinue
Remove-Item Env:VAULT_UNSEAL_KEY_2 -ErrorAction SilentlyContinue
Remove-Item Env:VAULT_UNSEAL_KEY_3 -ErrorAction SilentlyContinue
```

Shamir shares and the Vault administrative token are different materials. Terraform continues to require externally supplied `VAULT_ADDR` and `VAULT_TOKEN`; neither belongs in Git, Terraform variables, Helm values, Kubernetes manifests, documentation, or helper scripts.

### Production Seal Model

The local Shamir helper is not the production model.

Cloud development, QA, production, and recovery environments should use:

- Vault HA with integrated Raft
- TLS for client and cluster traffic
- cloud KMS or HSM auto-unseal
- cloud/workload identity for approved administration paths
- strict Kubernetes and Vault RBAC
- audit logging
- encrypted Terraform backend with locking

Examples:

- AWS: AWS KMS with workload or IAM identity
- Azure: Azure Key Vault or Managed HSM with Managed Identity
- GCP: Cloud KMS with Workload Identity

Cloud KMS auto-unseal is not implemented in Phase 7.

### Current Blocker

Phase 7 infrastructure work is blocked until an administrative Vault authentication mechanism is available to Terraform through the current execution environment.

Required environment:

- `VAULT_ADDR`
- `VAULT_TOKEN`

The token must be supplied externally and must not be pasted into chat or committed to the repository.

## Production Agent Access Control - Deferred

MCP, agent isolation, production Kubernetes access control, AWS agent access, and production credential management are intentionally not part of the current local Phase 1 lab.

Current Codex usage is limited to the local development environment. Production credentials must never be exposed to the development agent environment, and production administration is expected to use a separately controlled environment or device.

If agent-based production inspection is introduced later, it must use dedicated least-privilege identities and an appropriate isolation/control layer. Production write operations should remain human-controlled unless a separately approved security design is introduced.

No replacement MCP solution, VS Code MCP setup, Docker MCP Gateway, ToolHive setup, Dev Container isolation, or production credential control is implemented in Phase 1.
