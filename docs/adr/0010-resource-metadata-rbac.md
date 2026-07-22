# ADR 0010: Metadatos y RBAC de recursos academicos

## Estado

Aceptada

## Contexto

Las etapas 3A y 3B dejaron identidad institucional, perfiles, roles y Google OAuth
sin proteger todavia el catalogo ni almacenar archivos. El catalogo academico
sigue versionado en JSON. La etapa 4A debe preparar el modelo de metadatos y
autorizacion para recursos academicos antes de crear buckets R2, endpoints de
subida, descargas o revision UI.

## Decision

Crear en PostgreSQL las tablas:

- `public.academic_resources` para metadatos revisables del recurso.
- `public.resource_files` para metadatos no sensibles de archivos.
- `private.resource_storage_objects` para `storage_key` y estado interno de
  almacenamiento.
- `public.resource_review_events` como bitacora append-only.

Crear los enums `resource_review_status`, `resource_storage_status`,
`resource_visibility` y `resource_rights_status`. `course_id` y
`academic_term_id` son referencias logicas al catalogo JSON; no se crean foreign
keys ficticias hacia datos que aun no viven en PostgreSQL.

La autorizacion se mantiene en PostgreSQL. Las politicas RLS y funciones
`SECURITY DEFINER` usan `auth.uid()`, perfiles activos y roles activos en
`public.user_roles`. No se leen roles desde el navegador ni desde metadata OAuth.

## Flujo

El flujo de metadatos es:

1. Un `contributor` o rol superior crea un recurso propio en `draft`.
2. La etapa futura de subida registrara metadatos de archivo y objeto privado en
   estado `uploading`.
3. Cuando R2 confirme escritura, una RPC transaccional marcara el objeto como
   `stored`.
4. El propietario envia el recurso a `pending` mediante RPC.
5. Un `reviewer` puede rechazarlo. Solo `moderator` y `administrator` pueden
   aprobarlo y publicarlo.

Las transiciones de `review_status` y `storage_status` no se hacen por `UPDATE`
directo de clientes. Se ejecutan mediante RPC transaccionales auditadas.

## RLS

- `anon` solo lee recursos `approved` con visibilidad `public`.
- Usuarios autenticados con perfil `active` leen recursos `approved` con
  visibilidad `public` o `restricted`.
- El propietario con rol `contributor` o superior lee, crea y edita sus recursos
  `draft` o `rejected`.
- `reviewer` lee recursos `pending` y puede rechazar, pero no aprobar.
- `moderator` y `administrator` pueden aprobar/publicar.
- Cuentas `suspended` o `disabled` pierden acceso autenticado.

`storage_key` vive solo en `private.resource_storage_objects`; no existe columna
publica ni grant directo para `anon` o `authenticated`.

## Derechos

`bibliographic-reference-only` permite aprobar metadatos sin archivo almacenado.
No permite registrar archivos almacenados. `copyright-restricted` impide la
aprobacion. Si hay archivos almacenados, la aprobacion exige `own-work`,
`authorized` o `institutional`.

## Compensacion R2

4A no crea buckets ni escribe objetos. La etapa 4B debe insertar primero el
estado `uploading` en PostgreSQL, escribir R2 y luego marcar `stored` por RPC. Si
R2 se escribe pero PostgreSQL falla, el endpoint de 4B debe intentar borrar el
objeto inmediatamente. Si queda un registro `uploading` vencido, una tarea de
limpieza futura debera borrar el objeto y marcar `failed` o `delete_pending`.

## Seguridad

No se usa `service_role` en Astro. No se crean URLs publicas ni se exponen claves
de storage. Los eventos de revision son append-only. Las funciones definer fijan
`search_path` vacio, usan referencias calificadas y no usan SQL dinamico.

## Consecuencias

- La base de datos ya puede autorizar metadatos de recursos y revision sin R2.
- El catalogo JSON permanece como fuente de cursos y periodos durante 4A.
- 4B puede enfocarse en subida binaria y compensacion R2.
- 4C puede enfocarse en UI de revision, aprobacion y descarga server-side.

## Alternativas consideradas

- Guardar `storage_key` en una tabla publica: rechazado porque facilitaria
  exposicion accidental de rutas internas.
- Crear foreign keys hacia el catalogo JSON: rechazado porque esos datos aun no
  existen en PostgreSQL.
- Permitir `UPDATE` directo de estados: rechazado porque salta auditoria y
  validaciones de transicion.
- Crear R2 en 4A: rechazado por alcance; 4A solo modela metadatos y RBAC.
