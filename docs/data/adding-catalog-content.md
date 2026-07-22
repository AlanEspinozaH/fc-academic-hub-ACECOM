# Agregar Contenido Al Catalogo

## Regla Base

Para agregar unidades academicas, planes, cursos, relaciones curriculares, periodos o recursos no se modifican componentes Astro. Se editan los archivos JSON en `src/content/catalog/` y se ejecuta el pipeline local.

```sh
npm run ci
```

Solo se deben registrar datos reales cuando exista una fuente disponible y documentada. Si un dato curricular no esta confirmado, debe quedar pendiente de verificacion en lugar de inventarse.

## Identidad De Cursos

- Cambiar `name` no rompe relaciones, porque las relaciones usan `Course.id`.
- Cambiar `slug` cambia la URL de detalle del curso en `/courses/[slug]`.
- Cambiar `id` exige migrar todas las referencias en `curriculum-courses.json`, `resources.json`, pruebas y documentacion relacionada.
- Nunca edites solo un `id` aislado. Haz la migracion de referencias en el mismo cambio y ejecuta las validaciones.

Convencion de cursos:

```text
course:<codigo-en-minusculas>
```

Ejemplos: `course:bma01`, `course:bfi01`, `course:cc421`.

Convencion de relaciones plan-curso:

```text
curriculum-course:<plan>:<codigo-en-minusculas>
```

Ejemplos: `curriculum-course:n6:cc421`, `curriculum-course:n6:bma01`.

## Agregar Una Unidad Academica

1. Editar `src/content/catalog/academic-units.json`.
2. Agregar un objeto con `id`, `slug`, `name`, `abbreviation`, `description`, `unitType` y `status`.
3. Usar `parentUnitId` salvo que `unitType` sea `faculty`.
4. Usar un `slug` unico, en minusculas y con guiones.
5. Documentar la fuente si el nombre corresponde a una unidad real.

## Agregar Un Plan Curricular

1. Editar `src/content/catalog/curricula.json`.
2. `academicUnitId` debe apuntar a un `AcademicUnit` existente con `unitType: "program"`.
3. `status` debe ser `active` o `historical`.
4. `effectivePeriod` puede ser un anio, rango o `pending-verification` si todavia no fue contrastado.
5. No cambies un plan existente solo para ajustar una relacion; primero verifica si su identificador sigue siendo valido.

## Agregar Un Curso

1. Editar `src/content/catalog/courses.json`.
2. Agregar solo datos propios del curso: codigo, slug, nombre, resumen, creditos, etiquetas y estado.
3. No agregar escuela, carrera, plan, ciclo recomendado ni prerrequisitos dentro de `Course`.
4. `id` debe cumplir `course:<codigo-en-minusculas>`.
5. `code` debe conservar el codigo en mayusculas.
6. `slug` debe ser unico para `/courses/[slug]` y comenzar con el codigo en minusculas seguido de guion.
7. Si los creditos no estan verificados, usar `"credits": null` y `"dataStatus": "pending-verification"`. La UI mostrara `Por verificar`, no cero.
8. No agregar etiquetas como `demostracion` a cursos reales.

Los componentes y paginas leeran automaticamente el curso por la capa `src/domain/catalog.ts`.

## Ubicar Un Curso En Un Plan

1. Editar `src/content/catalog/curriculum-courses.json`.
2. `id` debe seguir `curriculum-course:<plan>:<codigo-en-minusculas>`.
3. `curriculumId` debe apuntar a un plan existente.
4. `courseId` debe apuntar a un curso existente.
5. `recommendedCycle` expresa el ciclo solo dentro de ese plan.
6. `requirementType` debe ser `required`, `elective` o `pending-verification`.
7. Cada entrada en `prerequisiteCourseIds` debe apuntar a un curso existente y presente en el mismo plan.
8. No crear ciclos directos de prerrequisitos dentro del mismo plan.
9. No inventar prerrequisitos ni obligatoriedad si la fuente no lo confirma.

Para representar un curso comun, no dupliques el curso. Crea otra relacion `CurriculumCourse` apuntando al mismo `courseId` desde otro `curriculumId`.

## Agregar Un Periodo Academico

1. Editar `src/content/catalog/academic-terms.json`.
2. Usar `id` con forma `YYYY-1` o `YYYY-2`, por ejemplo `2027-1`.
3. `year` y `period` deben coincidir con el `id`.

## Agregar Un Recurso

1. Editar `src/content/catalog/resources.json`.
2. `courseId` debe apuntar a un curso existente.
3. `academicTermId`, si existe, debe apuntar a un periodo existente.
4. `demo` debe ser `true` mientras el recurso no sea real y verificado.
5. `fileAvailable` debe ser `false` hasta que exista almacenamiento configurado.
6. No agregar campos de URL, rutas a archivos, PDFs, TEX, ZIP, DOCX ni binarios.
7. Para `book-reference`, describir solo la referencia bibliografica; no enlazar ni almacenar libros.
8. No conviertas un recurso ficticio en real solo cambiando `courseId`.

## Verificacion

Ejecutar al menos:

```sh
npm run format:check
npm run lint
npm run check
npm run test
npm run build
```

`npm run ci` ejecuta el pipeline completo. La suite debe fallar si el catalogo queda inconsistente.
