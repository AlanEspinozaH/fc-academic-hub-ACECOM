# FC Academic Hub — instrucciones para Codex

## Propósito

Construir y mantener FC Academic Hub, una plataforma académica comunitaria para organizar cursos y recursos de la Facultad de Ciencias con:

* seguridad;
* moderación;
* bajo costo;
* mantenimiento simple.

## Arquitectura

* Astro + TypeScript estricto.
* Cloudflare Workers.
* Supabase Auth + PostgreSQL.
* PostgreSQL/RLS como autoridad de autorización.
* Cloudflare R2 privado para archivos.
* GitHub para código y revisión.

Separar dominio, aplicación, infraestructura y presentación.

## Fuentes normativas

Antes de implementar cambios relacionados con recursos, revisar:

* `docs/product/v1-product-contract.md`
* `docs/architecture/resource-access-contract.md`
* `docs/architecture/resource-file-policy.md`
* `docs/architecture/resource-upload-contract.md`
* `docs/architecture/authentication-and-authorization.md`
* `docs/security/role-model.md`
* `docs/operations/governance.md` cuando el cambio afecte designación, transferencia, continuidad o custodia operativa.
* ADR aceptados aplicables.

Si implementación y contrato divergen:

* el código actual describe el estado implementado;
* los contratos aceptados describen el objetivo de la etapa;
* el cambio debe hacer converger código, tests y documentación.

## Alcance de Stage 4C

Las etapas de Stage 4C tienen límites distintos.

### `4C.0A`

Es exclusivamente documental.

Si una tarea está identificada como `4C.0A`, no implementar comportamiento nuevo ni modificar con ese propósito:

```text
src/
supabase/migrations/
supabase/tests/
schema
RLS
RPC
wrangler/R2 runtime configuration
```

Solo deben alinearse contratos, ADR, documentación operativa y documentación de desarrollo.

### `4C.0B`

Es la primera etapa autorizada para realinear de forma ejecutable:

```text
schema
RLS
auth/identity
entitlements
rights
visibility
storage_key_version
RPC
tests
```

PDF puede continuar siendo el único formato operativo de upload después de `4C.0B`.

Las etapas posteriores habilitan lectura y formatos progresivamente según los contratos aceptados.

No anticipar trabajo de una etapa posterior para “completar” una etapa anterior.

## Reglas de producto

No ampliar sin modificar primero el contrato normativo:

* formatos o extensiones;
* `file_kind`;
* `visibility`;
* `rights_status`;
* roles;
* entitlements;
* tipos de identidad;
* endpoints;
* número de archivos por recurso.

No inferir nuevas funcionalidades por conveniencia de implementación.

## Archivos

* Un recurso admite como máximo un archivo principal en v1.
* Todo upload es contenido no confiable.
* Validar siempre server-side.
* R2 permanece privado.
* Nunca ejecutar ni compilar archivos aportados por usuarios.
* Markdown, TeX y source se presentan como texto plano en v1.
* No aceptar HTML, SVG, archives ni formatos fuera de la allowlist.
* No exponer `storage_key` al navegador.
* Hasta que la migración de storage layout de Stage 4C esté implementada y verificada, preservar el layout PDF vigente de 4B.
* Después de esa migración, todos los nuevos uploads deben utilizar `generic_v2` según `resource-file-policy.md`.
* No modificar la derivación de storage key únicamente en TypeScript o únicamente en PostgreSQL; el cambio de layout debe mantener alineados schema, metadata, resolución server-side y pruebas.

## Autorización

Mantener separados:

```text
identity != role != entitlement != resource audience
```

* `restricted` depende de identidad institucional activa.
* `privileged` depende de `privileged_material.read`.
* Un entitlement no concede roles editoriales.
* No autorizar mediante comparaciones runtime del email.
* No confiar en roles o permisos enviados por navegador.
* PostgreSQL/RLS es la autoridad de acceso.
* `approved + public` debe conservar acceso público incluso para cuentas suspendidas/disabled.
* Moderator no accede a drafts/rejected ajenos solo por su rol.
* Administrator conserva capacidades administrativas excepcionales.

## Moderación

* Contributor propone.
* Moderator revisa y decide la audiencia final.
* Moderator no puede aprobar su propio recurso.
* Administrator gestiona roles, identidades externas y entitlements.
* El sistema admite múltiples Moderators.
* V1 requiere una sola aprobación válida.

## Upload

Preservar las garantías existentes de 4B:

* reserva PostgreSQL;
* R2 privado;
* SHA-256;
* atomicidad PostgreSQL;
* compensación;
* idempotencia;
* tratamiento explícito de resultados desconocidos;
* auditoría;
* un archivo por recurso.

No simplificar el pipeline eliminando estas garantías.

## Seguridad

* Nunca versionar secretos, tokens o contraseñas.
* Mantener `.env*` ignorados excepto `.env.example`.
* No usar `service_role` en el runtime normal de Astro.
* Aplicar mínimo privilegio.
* Usar `SECURITY DEFINER` únicamente cuando sea necesario y con `search_path` seguro.
* No crear URLs públicas permanentes de R2.
* No confiar en MIME, filenames, roles o identificadores enviados por cliente como autoridad.

## Ingeniería

* Mantener TypeScript strict.
* Evitar `any` salvo justificación.
* No introducir dependencias sin necesidad clara.
* No desactivar validaciones para hacer pasar CI.
* Preferir cambios pequeños e incrementales.
* Evitar refactors cosméticos fuera del alcance.
* No modificar directamente `main`.
* No realizar operaciones remotas o despliegues sin autorización explícita.

## Tests

Todo cambio de comportamiento debe incluir pruebas.

Para políticas normativas, utilizar los identificadores definidos en los contratos cuando existan:

```text
RA-*  resource access
RF-*  resource files
RU-*  resource upload
AA-*  authentication/authorization
RM-*  roles/entitlements
```

Una regla normativa afectada debe tener cobertura suficiente para demostrarla.

## Finalización

Antes de terminar una tarea:

```sh
npm run ci
```

o ejecutar los controles equivalentes de:

* format;
* lint;
* typecheck;
* tests;
* build.

Además:

* revisar `git diff`;
* confirmar que no se introdujeron secretos;
* actualizar documentación afectada;
* informar archivos modificados;
* informar tests/comandos ejecutados;
* señalar cualquier contrato no implementado o riesgo restante.
