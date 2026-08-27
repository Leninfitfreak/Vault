# Primary Environment

The primary environment is the active runtime target.

Phase 2 uses Argo CD as the normal reconciler. Helm remains the render/package mechanism.

Validation-only render command:

```powershell
helm template orders-service ..\..\applications\orders-service -f ..\..\applications\orders-service\values\primary.yaml
```

Routine changes should be committed to Git and reconciled by Argo CD.
