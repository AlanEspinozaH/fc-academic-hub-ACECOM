# Resumen De Arquitectura

## Proposito

FC Academic Hub organizara cursos, examenes, apuntes, silabos y recursos para la comunidad de la Facultad de Ciencias. El sistema objetivo debe ser seguro, de bajo costo y mantenible por administradores estudiantes.

## Arquitectura De Etapa 2

La implementacion actual es una aplicacion Astro con TypeScript estricto y adaptador de Cloudflare. El catalogo publico usa Content Collections con datos JSON ficticios versionados en Git.

```text
Navegador
  -> Paginas publicas Astro
  -> Componentes de presentacion
  -> Capa de consulta src/domain/catalog.ts
  -> Content Collections src/content/catalog/*.json
  -> Validaciones de integridad src/domain/catalog-integrity.ts
```

No hay integracion activa con Supabase, PostgreSQL, R2, autenticacion ni roles.

## Modelo Academico

El modelo separa identidad del curso y ubicacion curricular:

- `AcademicUnit`: facultad, escuela o programa ficticio.
- `Curriculum`: version concreta del plan de estudios de un programa.
- `Course`: curso estable sin escuela, ciclo ni prerrequisitos intrinsecos.
- `CurriculumCourse`: relacion entre plan y curso, con ciclo, tipo obligatorio/electivo y prerrequisitos del plan.
- `AcademicResource`: metadatos ficticios asociados a un curso.

`src/domain/catalog.ts` construye `CourseCatalogItem` para que la UI vea un curso con todas sus ofertas curriculares sin conocer el almacenamiento.

## Rutas Publicas

- `/`: busqueda principal, accesos por ciclo, carrera y recursos recientes.
- `/schools`: listado prerenderizado de escuelas ficticias.
- `/schools/[slug]`: detalle prerenderizado de escuela, carreras, planes y cursos destacados.
- `/courses`: lista compacta filtrable por texto, carrera y ciclo.
- `/courses/[slug]`: detalle prerenderizado de curso con ciclo por plan curricular.
- `/resources`: listado filtrable por texto, tipo, periodo y disponibilidad de solucion.
- `/api/health`: endpoint JSON de estado.

`/courses` y `/resources` son bajo demanda porque sus filtros por query params funcionan sin JavaScript. Las paginas de detalle y escuelas se prerenderizan para reducir futuras invocaciones de Cloudflare Workers.

## Tema Visual

El layout usa variables CSS para tema claro y oscuro, respeta `prefers-color-scheme` y permite alternar con un boton en la cabecera. La preferencia se guarda en `localStorage`; un script inline temprano en el `<head>` fija `data-theme` antes de pintar para evitar destello del tema incorrecto.

## Limites De Codigo Fuente

- `src/content.config.ts` define esquemas de colecciones y loaders `file()`.
- `src/content/catalog/` contiene datos demo versionados.
- `src/domain/` contiene tipos, consultas, filtros y validaciones de integridad.
- `src/components/` contiene presentacion reutilizable.
- `src/pages/` contiene rutas Astro y endpoints API.
- `src/infrastructure/` contiene helpers que no son conceptos de dominio.

## Integridad Del Catalogo

La integridad se valida en dos lugares:

1. `src/content.config.ts` valida forma local de cada registro con Zod.
2. `src/domain/catalog-integrity.ts` valida relaciones cruzadas, duplicados, terminos y restricciones de storage.

Las pruebas unitarias cargan los JSON y ejecutan las validaciones. Las paginas cargan datos mediante `src/domain/catalog.ts`, que tambien valida antes de devolver el snapshot.

## Cloudflare

`astro.config.mjs` conserva el adaptador Cloudflare sin crear recursos y usa `prerenderEnvironment: 'node'` para prerenderizar contenido estatico durante el build local. `wrangler.jsonc` no declara KV, R2, D1 ni secrets.

El adaptador instalado habilita por defecto sesiones Astro con KV `SESSION` cuando no hay driver de sesion configurado. En etapa 2 no se usa `Astro.session`; el mensaje queda documentado en `docs/adr/0002-static-academic-catalog.md` y debe resolverse deliberadamente antes de cualquier despliegue futuro.

## Integraciones Futuras

Supabase Auth/PostgreSQL y storage privado en Cloudflare R2 quedan para etapas posteriores. La autorizacion debe validarse siempre en servidor, no inferirse desde roles enviados por el navegador.

La migracion a PostgreSQL deberia reemplazar la implementacion de `src/domain/catalog.ts` manteniendo contratos de dominio y componentes.

## Controles Operativos

CI instala dependencias con `npm ci` y ejecuta formato, lint, `astro check`, pruebas unitarias y build. El despliegue no es automatico y requiere autorizacion explicita.
