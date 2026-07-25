# Vista general de arquitectura

FC Academic Hub usa Astro con TypeScript estricto para la aplicación web y datos estáticos versionados en Git para el catálogo académico.

La arquitectura incorpora Supabase/PostgreSQL para autenticación, identidad, roles, autorización, auditoría, RLS y metadata de recursos académicos.

Los archivos académicos utilizan almacenamiento privado en Cloudflare R2 mediante integración server-side. El baseline actualmente implementado continúa especializado en PDF, mientras Stage 4C define la evolución hacia archivos genéricos y nuevas reglas de acceso.

## Capas

* `src/content/catalog/`: JSON activos del catálogo académico.
* `src/domain/`: tipos, consultas, filtros, validaciones de integridad y lógica de dominio.
* `src/components/` y `src/pages/`: interfaz y endpoints Astro.
* `src/lib/` y módulos server-side relacionados: integración con Supabase, autorización, upload y almacenamiento.
* `docs/`: contratos de producto, arquitectura, seguridad y ADR.
* `supabase/`: configuración local, migraciones PostgreSQL, RLS, RPC y pruebas pgTAP.

## Catálogo estático

La aplicación carga Content Collections desde JSON y construye una vista `CourseCatalogItem` que relaciona cada `Course` con sus ubicaciones `CurriculumCourse`.

El catálogo académico continúa versionado en Git.

Una migración futura del catálogo hacia PostgreSQL puede sustituir la capa de consulta sin cambiar innecesariamente el contrato conceptual del dominio.

## Autenticación y autorización

Google OAuth se integra mediante Supabase Auth.

Astro mantiene contexto de autenticación por request, mientras PostgreSQL continúa siendo la autoridad para decisiones de aplicación relacionadas con:

```text
identity_kind
account_status
roles
entitlements
ownership
review_status
visibility
rights_status
```

El runtime normal de Astro no utiliza `service_role` para operaciones de usuario.

Las reglas objetivo de Stage 4C se definen principalmente en:

```text
docs/architecture/authentication-and-authorization.md
docs/architecture/resource-access-contract.md
docs/security/role-model.md
```

## Recursos y archivos

El modelo de recursos académicos utiliza PostgreSQL para metadata, workflow y autorización.

Cloudflare R2 se utiliza como almacenamiento privado de archivos mediante acceso server-side.

El baseline actualmente presente en `main` implementa el pipeline de subida especializado en PDF.

Stage 4C evoluciona ese modelo hacia:

```text
ResourceFile
```

con soporte progresivo para los formatos definidos en:

```text
docs/architecture/resource-file-policy.md
```

La coordinación transaccional PostgreSQL/R2 y las garantías heredadas de Stage 4B se definen en:

```text
docs/architecture/resource-upload-contract.md
```

## Estado de infraestructura

El repositorio contiene la integración y configuración necesarias para desarrollar localmente con Supabase y Cloudflare R2.

La existencia de bindings, adaptadores o configuración local no implica por sí sola que exista infraestructura remota productiva desplegada.

El estado concreto de despliegue remoto debe documentarse separadamente cuando corresponda.
