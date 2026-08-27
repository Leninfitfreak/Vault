# Argo CD GitOps Foundation

Phase 2 introduces Argo CD as the reconciler for the existing Helm chart. Helm remains the packaging and rendering mechanism; Argo CD becomes the controller that continuously reconciles Kubernetes state from Git.

## Bootstrap

Argo CD is bootstrapped once into `vault-primary`:

```powershell
kubectl --context vault-primary apply -k gitops/argocd/bootstrap --server-side --force-conflicts
```

The bootstrap uses the official Argo CD install manifest from the stable branch. Production environments should pin a reviewed Argo CD release tag before adoption.

## GitOps Resources

After Argo CD is healthy and the repository is published to the configured Git URL, apply:

```powershell
kubectl --context vault-primary apply -k gitops/argocd/projects
kubectl --context vault-primary apply -k gitops/argocd/applications
```

## Cluster Registration

The primary application targets the in-cluster destination `https://kubernetes.default.svc`.

The recovery application targets an Argo CD cluster registration named `vault-dr`. Register only that cluster; do not expose unrelated kubeconfig contexts to Argo CD. Repository credentials and cluster tokens must be configured out of band and must not be committed to Git.

## ApplicationSet Decision

ApplicationSet is deferred. Two explicit Applications are clearer for this local two-environment foundation and keep the first GitOps handoff easy to audit.
