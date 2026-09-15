[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "Required command 'kubectl' was not found in PATH."
}

kubectl cluster-info | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "kubectl cannot access the current cluster."
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$rootApplication = Join-Path $repositoryRoot "argocd\root-app.yaml"

if (-not (Test-Path -LiteralPath $rootApplication -PathType Leaf)) {
    throw "Root Application manifest not found: $rootApplication"
}

Write-Host "Applying only the one-time App of Apps bootstrap manifest..."
kubectl apply -f $rootApplication | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Root Application bootstrap failed."
}

Write-Host "Root Application submitted. Child Applications remain Git-managed by Argo CD."
kubectl get application docket-dev-root -n argocd | Out-Host
