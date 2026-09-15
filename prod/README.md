# Production environment

Production is intentionally a skeleton. No production manifests or Argo CD Applications exist yet.

Production enablement requires an approved platform design, Terraform-managed namespaces and infrastructure, immutable CI-published ECR tags, environment-specific configuration, secret-management controls, and a reviewed Argo CD promotion workflow. Do not copy DEV Secrets or credentials into Git.
