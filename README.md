# SINTRATEL Docket GitOps manifests

This repository is the deployment source of truth for the SINTRATEL Docket Kubernetes applications. Argo CD reads the desired state from `main` and continuously reconciles the DEV cluster to match it.

## Ownership boundaries

| Concern | Owner |
| --- | --- |
| Tests, Docker builds, semantic/versioned tags, ECR pushes | Application CI pipelines |
| Deployments, Services, supporting ConfigMaps, desired image references, reconciliation | This repository and Argo CD |
| VPC, EKS, namespaces, ECR, IAM/OIDC, infrastructure lifecycle | `docket-infra` and Terraform |

This repository does not build or publish images and does not create namespaces or cloud infrastructure. Application images use immutable, CI-published tags; `latest` is forbidden.

## Repository layout

```text
.
|-- argocd/
|   `-- root-app.yaml
|-- dev/
|   |-- apps/                       # five Argo CD child Applications
|   |-- frontend/                   # Deployment and ClusterIP Service
|   |-- auth-api/                   # Deployment and ClusterIP Service
|   |-- users-api/                  # Deployment and ClusterIP Service
|   |-- todos-api/                  # API plus its internal Redis dependency
|   `-- log-message-processor/      # worker Deployment; no Service
|-- staging/
`-- prod/
```

DEV is the only configured environment. `staging/` and `prod/` are intentional skeletons and have no Argo CD Applications yet.

## App of Apps

`argocd/root-app.yaml` defines `docket-dev-root`. It tracks `main`, reads `dev/apps`, and manages exactly five child Applications:

| Application | Git path | Destination namespace |
| --- | --- | --- |
| `frontend` | `dev/frontend` | `dev-frontend` |
| `auth-api` | `dev/auth-api` | `dev-auth-api` |
| `users-api` | `dev/users-api` | `dev-users-api` |
| `todos-api` | `dev/todos-api` | `dev-todos-api` |
| `log-message-processor` | `dev/log-message-processor` | `dev-log-message-processor` |

Every Application uses automated sync with `enabled: true`, `prune: true`, and `selfHeal: true`. Argo CD therefore applies changes merged to `main`, removes objects deleted from Git, and reverts live drift. `CreateNamespace=true` is intentionally absent because Terraform owns all five namespaces.

Redis is required by the application source. Its Deployment and internal ClusterIP Service are managed by the `todos-api` Application in `dev-todos-api`. The worker uses the cross-namespace address `redis.dev-todos-api.svc.cluster.local`. Redis is supporting software, not a sixth microservice Application.

## Image versions

Images come from account `429418377318` in `us-east-1`:

```text
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/frontend
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/auth-api
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/users-api
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/todos-api
429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/log-message-processor
```

The ECR repositories were recreated and could not be inspected while this repository was initialized. Each microservice manifest therefore contains the explicit non-deployable tag `__IMAGE_TAG_PENDING_CI__`. Do not bootstrap these Applications for runtime use until CI has published real immutable tags and all placeholders have been replaced.

To update a version, edit only the applicable Deployment image, for example:

```yaml
image: 429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/todos-api:1.2.3-abc1234
```

Commit the change and merge it to `main`. Do not run a manual Argo sync. Confirm the automatic rollout with:

```bash
kubectl rollout status deployment/todos-api -n dev-todos-api
kubectl get pods -n dev-todos-api
```

Before committing, ensure no placeholder remains:

```bash
rg '__IMAGE_TAG_PENDING_CI__' dev
```

## JWT Secret prerequisite

`auth-api`, `users-api`, and `todos-api` require the same JWT signing value. Their Deployments reference a Secret named `docket-jwt` with key `jwt-secret` in their respective namespaces. Secret values must never be committed here. A platform operator must provision that Secret out of band in:

- `dev-auth-api`
- `dev-users-api`
- `dev-todos-api`

One safe input pattern is a protected local file:

```bash
kubectl create secret generic docket-jwt -n <namespace> --from-file=jwt-secret=/secure/path/jwt-secret
```

Repeat for each required namespace using the same protected value. Do not paste or log the value.

## Install Argo CD

Live installation requires authenticated access to AWS account `429418377318`, the ACTIVE `docket-dev` EKS cluster, and at least one Ready node. The [official Argo Helm chart](https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/Chart.yaml) is pinned to `10.9.0` (Argo CD `v3.5.2`). Helm is not currently installed on the initializing workstation.

```bash
aws sts get-caller-identity
aws eks describe-cluster --name docket-dev --region us-east-1
aws eks update-kubeconfig --region us-east-1 --name docket-dev
kubectl get nodes
kubectl get namespaces

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.9.0 \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --wait --timeout 10m

kubectl get pods -n argocd
kubectl get svc -n argocd
```

No Ingress or public LoadBalancer is used.

## Bootstrap and inspect

Merge the feature branch to `main` and replace all pending image tags before the one-time root bootstrap:

```bash
kubectl apply -f argocd/root-app.yaml
kubectl get applications -n argocd
kubectl get application docket-dev-root -n argocd
```

Expected Applications are `docket-dev-root`, `frontend`, `auth-api`, `users-api`, `todos-api`, and `log-message-processor`.

If the Argo CD CLI is installed:

```bash
argocd app get docket-dev-root
argocd app get todos-api
```

## Internal UI access

Forward the internal ClusterIP service:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080`. Retrieve the initial password without writing it to Git:

```bash
argocd admin initial-password -n argocd
```

If the Argo CD CLI is unavailable, use Kubernetes directly (the command prints the password only to the current terminal):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode
```

The initial username is `admin`. Rotate or disable the initial credential according to platform policy after first login.

## Reconciliation validation

After bootstrap, validate automated sync without manually applying the changed resource:

1. Change `gitops.sintratel.io/reconciliation-marker` on a Deployment pod template.
2. Commit and merge the change to `main`.
3. Observe `OutOfSync` followed by `Synced` with `kubectl get applications -n argocd -w`.
4. Confirm the live annotation with `kubectl get deployment <name> -n <namespace> -o jsonpath='{.spec.template.metadata.annotations}'`.

Validate self-heal by changing only that harmless live annotation:

```bash
kubectl annotate deployment/todos-api -n dev-todos-api \
  gitops.sintratel.io/reconciliation-marker=temporary-drift --overwrite
kubectl get application todos-api -n argocd -w
kubectl get deployment/todos-api -n dev-todos-api \
  -o jsonpath='{.spec.template.metadata.annotations.gitops\.sintratel\.io/reconciliation-marker}'
```

Argo CD should restore the Git value. Do not commit the drift and do not alter Secrets or critical fields. `prune: true` is configured; any prune test should use only a disposable Git-managed ConfigMap.

## Pending live execution

Repository construction can proceed without cluster access, but these steps remain cluster-dependent:

1. Authenticate to AWS account `429418377318`.
2. Verify `docket-dev` is ACTIVE and update kubeconfig.
3. Verify at least one node is Ready and all Terraform-owned DEV namespaces exist.
4. Inspect ECR and replace every pending tag with a real immutable CI-published tag.
5. Provision the three `docket-jwt` Secrets out of band.
6. Install Helm if needed, then install pinned Argo CD in `argocd`.
7. Verify all Argo CD pods and Services.
8. Merge the GitOps pull request to `main`.
9. Apply `argocd/root-app.yaml` once.
10. Verify the root and five child Applications.
11. Validate automated sync and self-heal.
12. Commit a later real image-tag update and observe the automatic rollout without manual sync.

At initialization, live validation was blocked because AWS CLI had no configured credentials and `C:\Users\juanp\.kube\config` was inaccessible to the current process.
