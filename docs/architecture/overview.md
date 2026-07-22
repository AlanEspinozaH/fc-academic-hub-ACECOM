# Vista general de arquitectura

FC Academic Hub usa Astro con TypeScript estricto y datos estaticos versionados en Git para el catalogo. La etapa 3A.1 agrega fundamentos locales de Supabase/PostgreSQL para identidad, roles, permisos, auditoria y RLS, sin integrar autenticacion en paginas Astro.

## Capas

- `src/content/catalog/`: JSON activos del catalogo academico.
- `src/domain/`: tipos, consultas, filtros y validaciones de integridad; matriz local de roles y permisos.
- `src/components/` y `src/pages/`: presentacion Astro sin framework cliente.
- `docs/`: modelo de datos, guias, seguridad y ADR.
- `supabase/`: configuracion local, migraciones PostgreSQL y pruebas pgTAP.

## Catalogo estatico

La aplicacion carga Content Collections desde JSON y construye una vista `CourseCatalogItem` que une cada `Course` con sus ubicaciones `CurriculumCourse`.

El almacenamiento futuro del catalogo puede migrar a PostgreSQL reemplazando la capa de consulta sin cambiar el contrato conceptual del dominio. La etapa 3A.1 no migra cursos, planes, relaciones ni recursos.

## Limites vigentes

No hay login, OAuth, cookies, middleware, clientes Supabase en Astro, R2, carga de documentos ni URLs permanentes de archivos privados.

Supabase/PostgreSQL existe solo como base local versionada para RBAC y RLS. Los recursos permanecen vacios hasta que exista una etapa con almacenamiento y reglas de autorizacion.
