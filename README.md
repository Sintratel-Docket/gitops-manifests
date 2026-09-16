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
|   |-- apps/                       # workload, validation, and gateway Applications
|   |-- gateway/                    # GatewayClass, Gateway, and AWS LB configuration
|   |-- frontend/                   # Deployment, ClusterIP Service, and HTTPRoute
|   |-- auth-api/                   # Deployment and ClusterIP Service
|   |-- users-api/                  # Deployment and ClusterIP Service
|   |-- todos-api/                  # API plus its internal Redis dependency
|   |-- gitops-validation/          # harmless reconciliation test ConfigMap
|   `-- log-message-processor/      # worker Deployment; no Service
|-- staging/
`-- prod/
```

DEV is the only configured environment. `staging/` and `prod/` are intentional skeletons and have no Argo CD Applications yet.

## App of Apps

`argocd/root-app.yaml` defines `docket-dev-root`. It tracks `main`, reads `dev/apps`, and manages the five microservice Applications, one isolated validation Application, and the shared gateway Application:

| Application | Git path | Destination namespace |
| --- | --- | --- |
| `frontend` | `dev/frontend` | `dev-frontend` |
| `auth-api` | `dev/auth-api` | `dev-auth-api` |
| `users-api` | `dev/users-api` | `dev-users-api` |
| `todos-api` | `dev/todos-api` | `dev-todos-api` |
| `log-message-processor` | `dev/log-message-processor` | `dev-log-message-processor` |
| `gitops-validation` | `dev/gitops-validation` | `dev-frontend` |
| `gateway` | `dev/gateway` | `dev-frontend` |

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

Each Deployment references a real immutable tag published by its application CI pipeline. Git remains the only place where deployed image versions are selected; `latest` and invented tags are forbidden.

To update a version, edit only the applicable Deployment image, for example:

```yaml
image: 429418377318.dkr.ecr.us-east-1.amazonaws.com/docket/todos-api:1.2.3-abc1234
```

Commit the change and merge it to `main`. Do not run a manual Argo sync. Confirm the automatic rollout with:

```bash
kubectl rollout status deployment/todos-api -n dev-todos-api
kubectl get pods -n dev-todos-api
```

Before committing, ensure no placeholder or mutable `latest` tag remains:

```bash
rg '__IMAGE_TAG_PENDING_CI__' dev
rg ':latest' dev
```

## Gateway API routing

DEV has one public entry point and keeps every application Service as `ClusterIP`:

```text
Internet
  -> one internet-facing AWS Application Load Balancer
  -> docket-dev-gateway (Gateway, port 80)
  -> frontend (HTTPRoute PathPrefix /, IP targets on port 8080)
  -> frontend runtime proxy
       /login -> auth-api -> users-api
       /todos -> todos-api -> Redis
```

The worker has no Service and remains private. `auth-api`, `users-api`, `todos-api`, and Redis are also private; the frontend's existing runtime proxy provides the same-origin API paths, so no browser configuration or image rebuild is required.

Routing uses Kubernetes Gateway API instead of Ingress. `GatewayClass/docket-alb` selects the AWS Load Balancer Controller. The namespaced `LoadBalancerConfiguration/docket-dev-alb-config` requests one internet-facing IPv4 ALB, and `TargetGroupConfiguration/frontend-ip-targets` explicitly selects `ip` targets for the frontend Service. `Gateway/docket-dev-gateway` permits HTTPRoutes only from namespaces labeled `environment=dev`; the only public route is `HTTPRoute/frontend` in `dev-frontend`.

The `gateway` Argo CD Application owns these resources. Changes must be merged to `main` and reconciled automatically; do not apply routing manifests or trigger a manual sync. The shared ALB incurs AWS cost while it exists.

Inspect the reconciled route and AWS resources with:

```bash
kubectl get gatewayclass docket-alb
kubectl get gateway docket-dev-gateway -n dev-frontend
kubectl get httproute frontend -n dev-frontend
kubectl get ingress -A
aws elbv2 describe-load-balancers --region us-east-1
aws elbv2 describe-target-groups --region us-east-1
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

On Windows, the same pinned and internal-only installation is automated by:

```powershell
.\scripts\install-argocd.ps1
.\scripts\verify-argocd.ps1
```

Argo CD itself remains internal: its Service is `ClusterIP` and no Ingress exposes it. The public application entry point is the single Gateway-managed ALB described above; no application Service uses type `LoadBalancer`.

## Bootstrap and inspect

Merge the feature branch to `main` before the one-time root bootstrap. Pending image tags will leave the affected workloads unhealthy, but do not prevent the validation ConfigMap from reconciling:

```bash
kubectl apply -f argocd/root-app.yaml
kubectl get applications -n argocd
kubectl get application docket-dev-root -n argocd
```

On Windows, bootstrap only the root Application with:

```powershell
.\scripts\bootstrap-root-app.ps1
```

Expected Applications are `docket-dev-root`, `frontend`, `auth-api`, `users-api`, `todos-api`, `log-message-processor`, `gitops-validation`, and `gateway`.

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

The dedicated `gitops-validation` Application owns only `dev/gitops-validation/configmap.yaml` in the existing Terraform-owned `dev-frontend` namespace. It does not replace the final image-rollout Definition of Done.

After bootstrap, validate automated sync without manually applying the changed resource:

1. Confirm `gitops-validation` is Synced and the ConfigMap declares `validation-version: "1"`.
2. Change `validation-version` in Git from `"1"` to `"2"`.
3. Commit and merge the change to `main`.
4. Do not run `argocd app sync` or `kubectl apply`.
5. Observe `OutOfSync` followed by `Synced` with `kubectl get applications -n argocd -w`.
6. Confirm the live value:

```bash
kubectl get configmap gitops-validation -n dev-frontend \
  -o jsonpath='{.data.validation-version}'
```

With Git still declaring `"2"`, validate self-heal by changing only the live ConfigMap:

```bash
kubectl patch configmap gitops-validation -n dev-frontend --type merge \
  -p '{"data":{"validation-version":"manual-drift"}}'
kubectl get application gitops-validation -n argocd -w
kubectl get configmap gitops-validation -n dev-frontend \
  -o jsonpath='{.data.validation-version}'
```

Argo CD should restore `"2"`. Do not commit the drift. `prune: true` is configured; any prune demonstration must use only another disposable resource in `dev/gitops-validation`.

The pod-template reconciliation marker remains available for later workload-specific checks:

1. Change `gitops.sintratel.io/reconciliation-marker` on a Deployment pod template.
2. Commit and merge the change to `main`.
3. Observe `OutOfSync` followed by `Synced` with `kubectl get applications -n argocd -w`.
4. Confirm the live annotation with `kubectl get deployment <name> -n <namespace> -o jsonpath='{.spec.template.metadata.annotations}'`.

## Current live state

The `docket-dev` cluster, Terraform-owned namespaces, Argo CD installation, root Application, automated sync, self-heal behavior, immutable application images, and healthy workloads have been validated. Gateway routing is reconciled through the same App-of-Apps flow after its change is merged to `main`.
