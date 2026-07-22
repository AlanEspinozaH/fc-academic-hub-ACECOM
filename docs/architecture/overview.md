# Vista general de arquitectura

FC Academic Hub usa Astro con TypeScript estricto y datos estaticos versionados en Git durante esta etapa.

## Capas

- `src/content/catalog/`: JSON activos del catalogo academico.
- `src/domain/`: tipos, consultas, filtros y validaciones de integridad.
- `src/components/` y `src/pages/`: presentacion Astro sin framework cliente.
- `docs/`: modelo de datos, guias y ADR.

## Catalogo estatico

La aplicacion carga Content Collections desde JSON y construye una vista `CourseCatalogItem` que une cada `Course` con sus ubicaciones `CurriculumCourse`.

El almacenamiento futuro puede migrar a PostgreSQL reemplazando la capa de consulta sin cambiar el contrato conceptual del dominio.

## Limites vigentes

No hay Supabase, PostgreSQL, autenticacion, roles, R2, carga de documentos ni URLs permanentes de archivos privados.

Los recursos permanecen vacios hasta que exista una etapa con almacenamiento y reglas de autorizacion.
