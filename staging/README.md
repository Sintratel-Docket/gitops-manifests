# Staging environment

Staging is intentionally a skeleton. No staging manifests or Argo CD Applications exist yet.

When promoted, staging must use its own Terraform-managed namespaces, immutable CI-published ECR tags, environment-specific configuration, and a reviewed Argo CD root/child Application hierarchy. Do not copy DEV Secrets or credentials into Git.
