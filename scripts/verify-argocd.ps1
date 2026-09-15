[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "Required command 'kubectl' was not found in PATH."
}

Write-Host "Kubernetes context:"
kubectl config current-context | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "No usable Kubernetes context is configured."
}

kubectl cluster-info | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "kubectl cannot access the current cluster."
}

Write-Host "Argo CD pods:"
kubectl get pods -n argocd -o wide | Out-Host

Write-Host "Argo CD services:"
kubectl get svc -n argocd | Out-Host

Write-Host "Argo CD Deployments and StatefulSets:"
kubectl get deployments,statefulsets -n argocd | Out-Host

Write-Host "Argo CD Applications:"
kubectl get applications.argoproj.io -n argocd | Out-Host

Write-Host "Deployment rollout status:"
kubectl rollout status deployment --all -n argocd --timeout=120s | Out-Host

Write-Host "Expected Applications after root bootstrap:"
Write-Host "  docket-dev-root, frontend, auth-api, users-api, todos-api, log-message-processor, gitops-validation"
