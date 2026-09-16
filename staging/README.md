# Staging environment

Staging mirrors the dev workloads with environment-specific namespaces, service DNS names, Gateway resources, and Argo CD Applications. It uses immutable CI-published ECR tags promoted from dev.

The `docket-staging` cluster must be registered in the central Argo CD instance before these Applications can synchronize. Create the required `docket-jwt` Secrets outside Git; do not store credentials in this repository.
