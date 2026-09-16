# GitOps image promotion

This repository promotes an image that has already been published to ECR through three environment-specific manifests:

```text
image published once in ECR
  -> DEV
  -> pull request for staging
  -> pull request for production
```

The image is built once. Promotion does not rebuild, retag, or copy it. Each environment declares the exact same immutable image reference in its own Deployment manifest, and each promotion is reviewed and merged through a pull request to `gitops-manifests`.

After a promotion is merged to `main`, Argo CD detects the declared change and reconciles the target environment. Do not use `kubectl set image`, manual `kubectl apply`, direct cluster edits, or other ad hoc changes to promote a version.

## Promotion example

For example, the current `todos-api` image reference is:

```text
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/todos-api:1.1.0-f330d30
```

The environment-specific manifests are:

```text
dev/todos-api/deployment.yaml
staging/todos-api/deployment.yaml
prod/todos-api/deployment.yaml
```

A promotion changes only this field in the target environment manifest:

```text
spec.template.spec.containers[0].image
```

Copy the complete image reference from the previously validated environment. Keep the registry, repository, version, and commit suffix unchanged.

## Environment flow

### DEV

1. Update the DEV Deployment manifest with the new immutable image reference.
2. Merge the change through a pull request.
3. Let Argo CD deploy the image automatically.
4. Validate the rollout and application behavior in DEV.
5. If validation passes, open a staging promotion pull request with the same image reference.

### Staging

1. Update the staging Deployment manifest with the exact image reference validated in DEV.
2. Merge the change through a pull request.
3. Let Argo CD synchronize staging automatically.
4. Validate the rollout and application behavior in staging.
5. If validation passes, open a production promotion pull request with the same image reference.

### Production

1. Update the production Deployment manifest with the exact image reference validated in staging.
2. Merge the change through a pull request.
3. Let Argo CD reconcile production automatically.
4. Validate the rollout and production behavior. No rebuild occurs during this step.

## Declared sync policy

The current Applications for all three environments declare automated synchronization with pruning and self-healing enabled:

| Environment | Automated | Prune | Self-heal |
| --- | --- | --- | --- |
| DEV | Enabled | Enabled | Enabled |
| Staging | Enabled | Enabled | Enabled |
| Production | Enabled | Enabled | Enabled |

After a merge, the target environment can begin reconciling without a separate manual sync step.

## Rollback

Rollback through Git so the repository remains the source of truth:

1. Revert the promotion pull request, or open a new pull request that restores the previously validated image reference.
2. Review and merge the rollback change.
3. Let Argo CD reconcile the environment to the restored reference.
4. Verify the rollout and application behavior.

Manual Kubernetes image changes are not the normal rollback path because Argo CD self-healing restores the state declared in Git.

## Operational prerequisites

Before a live staging or production promotion:

- Register the clusters in the central Argo CD instance as `docket-staging` and `docket-prod`.
- Provision the environment namespaces managed by Terraform.
- Provision the external `docket-jwt` Secret in each namespace that requires it. Never store its value in Git.
- Install the Gateway API CRDs.
- Install and configure the AWS Load Balancer Controller.
- Ensure the clusters can authenticate to and pull from ECR.
- Confirm that the selected immutable image reference is already published in ECR.

## Evidence for completion

Retain the following evidence for each release without inventing or backfilling unavailable data:

- DEV pull request
- Staging pull request
- Production pull request
- Manifest commit
- Image tag
- Image digest, when available
- Argo CD `Synced` and `Healthy` status
- Successful rollout
- Functional validation result
