[CmdletBinding()]
param(
    [string]$ChartVersion = "10.9.0"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

Assert-Command -Name "helm"
Assert-Command -Name "kubectl"

Write-Host "Verifying Kubernetes cluster access..."
kubectl cluster-info | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "kubectl cannot access the current cluster."
}

$argocdNamespace = kubectl get namespace argocd --ignore-not-found -o name
if ($LASTEXITCODE -ne 0) {
    throw "Failed to check whether namespace 'argocd' exists."
}

if (-not $argocdNamespace) {
    Write-Host "Creating the Argo CD namespace..."
    kubectl create namespace argocd | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create namespace 'argocd'."
    }
}

Write-Host "Configuring the official Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure the Argo Helm repository."
}

helm repo update | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Failed to update Helm repositories."
}

Write-Host "Installing or upgrading Argo CD chart $ChartVersion..."
helm upgrade --install argocd argo/argo-cd `
    --version $ChartVersion `
    --namespace argocd `
    --set server.service.type=ClusterIP `
    --set server.ingress.enabled=false `
    --wait `
    --timeout 10m | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Argo CD Helm installation failed."
}

Write-Host "Waiting for all Argo CD pods to become Ready..."
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=600s | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "One or more Argo CD pods did not become Ready."
}

kubectl get pods -n argocd | Out-Host
kubectl get svc -n argocd | Out-Host

Write-Host "Argo CD is installed with an internal ClusterIP service."
