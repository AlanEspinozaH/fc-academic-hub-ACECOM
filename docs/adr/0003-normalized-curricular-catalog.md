# ADR 0003: Modelo Curricular Normalizado

## Estado

Aceptada

## Contexto

El primer catalogo estatico de etapa 2 modelaba `schoolId`, `recommendedCycle`, `curriculumIds` y `prerequisiteCourseIds` dentro de `Course`. Eso duplicaba responsabilidades: un curso puede existir en varios planes, cambiar de ciclo segun el plan y tener prerrequisitos curriculares distintos.

Antes de comenzar autenticacion conviene corregir el modelo para que la futura migracion a PostgreSQL no herede un acoplamiento incorrecto.

## Decision

Separar el curso de su ubicacion curricular:

- `AcademicUnit` representa facultad, escuelas y programas mediante `unitType` y `parentUnitId`.
- `Curriculum` representa una version concreta del plan de estudios de un programa.
- `Course` representa solo el curso estable: codigo, slug, nombre, resumen, creditos, etiquetas y estado.
- `CurriculumCourse` relaciona `curriculumId`, `courseId`, `recommendedCycle`, `requirementType` y `prerequisiteCourseIds`.

La UI consume `CourseCatalogItem`, una vista derivada por `src/domain/catalog.ts` que junta el curso con sus ofertas curriculares.

## Consecuencias

- Un curso comun de primer ciclo se registra una sola vez en `courses.json` y aparece varias veces en `curriculum-courses.json`, una por plan.
- El ciclo recomendado y los prerrequisitos pueden variar por plan curricular sin duplicar cursos.
- Las validaciones de integridad se mueven a relaciones curriculum-curso: planes inexistentes, cursos inexistentes, prerrequisitos inexistentes, prerrequisitos fuera del mismo plan y ciclos circulares directos.
- La migracion futura a PostgreSQL puede mapear estas colecciones a tablas normalizadas con menos cambios conceptuales.

## UI Y Tema

La etapa 2 tambien se compacto visualmente para preparar flujos operativos:

- La home prioriza busqueda, acceso por ciclo, acceso por carrera y recursos recientes.
- `/courses` usa lista compacta en lugar de tarjetas para el catalogo completo.
- Las tarjetas quedan para vistas destacadas y recursos recientes.
- El tema oscuro usa variables CSS, `prefers-color-scheme`, un control accesible en la cabecera y persistencia en `localStorage`.

## Alternativas Consideradas

- Mantener `recommendedCycle` dentro de `Course`: rechazado porque el mismo curso puede tener ciclos distintos por plan.
- Duplicar cursos por carrera: rechazado porque rompe identidad estable del curso y complica recursos asociados.
- Crear una entidad `School` separada y otra `Program`: rechazado por ahora para mantener una sola jerarquia `AcademicUnit` que representa facultad, escuela y programa.
