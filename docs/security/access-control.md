# Control de acceso y promoción controlada — SINTRATEL Docket

Este documento describe las decisiones de seguridad de acceso y despliegue del
proyecto (issue #9): promoción controlada a producción, aprobación de cambios,
RBAC en Kubernetes y TLS.

## 1. Promoción controlada entre ambientes

La imagen se construye **una sola vez** en el CI de cada microservicio y se
publica con un tag inmutable en ECR. Promover = mover ese mismo tag entre las
carpetas de ambiente en este repositorio (`dev/` → `staging/` → `prod/`), y
Argo CD sincroniza cada ambiente.

| Ambiente | Política de sync de Argo CD | Cómo se despliega |
| --- | --- | --- |
| dev | `automated` (self-heal, prune) | Automático al mergear a `main` |
| staging | `automated` (self-heal, prune) | Automático al mergear a `main` |
| **prod** | **manual** (`syncPolicy: {}`, sin `automated`) | Requiere **Sync explícito** en Argo CD |

Los `Application` de producción viven en `prod/apps/` y **no** tienen bloque
`automated`: aunque se mergee un cambio, Argo CD **no** despliega a prod hasta
que una persona ejecuta el sync.

## 2. Aprobación de cambios (gate humano)

- **CODEOWNERS** (`.github/CODEOWNERS`): los cambios bajo `prod/` y `argocd/`
  requieren la aprobación de un líder.
- **Branch protection** en `main`: *Require a pull request before merging*,
  *Require review from Code Owners* y al menos 1 aprobación.
- Consecuencia (segregación de funciones): **quien propone un cambio no puede
  aprobarlo**; debe revisarlo otra persona.

### Flujo de una promoción a producción

1. Se abre un PR que cambia el tag de imagen en `prod/<servicio>/deployment.yaml`.
2. Un líder (Code Owner) revisa y aprueba el PR.
3. Se mergea a `main`.
4. En Argo CD, el `Application` `prod-<servicio>` queda **OutOfSync** pero **no**
   se despliega solo.
5. Un operador ejecuta el **Sync manual** (UI o `argocd app sync prod-<servicio>`).
   Recién ahí el cambio llega a producción.

## 3. RBAC en Kubernetes

Se definen dos niveles de acceso, aplicando mínimo privilegio:

| Rol | ClusterRole | Grupo | Alcance |
| --- | --- | --- | --- |
| Solo lectura | `view` (integrado) | `docket:viewers` | Lectura de recursos (sin secrets) |
| Administración | `cluster-admin` (integrado) | `docket:admins` | Control total |

Los bindings se gestionan por GitOps en `dev/rbac/` (Application `rbac`).

### Cómo asignar un usuario a un rol

Los grupos de Kubernetes se asignan a identidades IAM mediante **EKS Access
Entries** (en Terraform, `docket-infra`). Ejemplo para un usuario de solo lectura:

```hcl
access_entries = {
  auditor = {
    principal_arn     = "arn:aws:iam::429418377318:user/Auditor"
    kubernetes_groups = ["docket:viewers"]
  }
}
```

Los administradores actuales (**JuanP**, **Karen**) tienen `cluster-admin` vía
**EKS Access Policy** (`AmazonEKSClusterAdminPolicy`), gestionada en Terraform.

## 4. TLS

Los servicios públicos se exponen a través de un ALB gestionado por el AWS
Gateway API controller. Como el proyecto no cuenta con un dominio propio, se usa
un **certificado autofirmado** importado en **AWS Certificate Manager (ACM)** y
referenciado en el listener HTTPS (443) del Gateway.

> Estado: en implementación (ver PR de TLS). El certificado autofirmado
> demuestra el cifrado en tránsito; un navegador mostrará una advertencia por no
> ser emitido por una CA pública, lo cual es esperado sin dominio real.

## 5. Otros controles de seguridad del proyecto

- **Sin credenciales de larga duración**: CI/infra se autentican a AWS vía
  **GitHub OIDC** (roles `GitHubActionsECRPush`, `GitHubActionsDocketInfra`).
- **ECR con tags inmutables** y `scan on push`.
- **Terraform remote state** en S3 con versioning, cifrado y locking.
