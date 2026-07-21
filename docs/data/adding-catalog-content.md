# Agregar Contenido Al Catalogo

## Regla Base

Para agregar unidades academicas, planes, cursos, relaciones curriculares, periodos o recursos no se modifican componentes Astro. Se editan los archivos JSON en `src/content/catalog/` y se ejecuta el pipeline local.

```sh
npm run ci
```

Los datos deben seguir siendo ficticios en etapa 2.

## Agregar Una Unidad Academica

1. Editar `src/content/catalog/academic-units.json`.
2. Agregar un objeto con `id`, `slug`, `name`, `abbreviation`, `description`, `unitType` y `status`.
3. Usar `parentUnitId` salvo que `unitType` sea `faculty`.
4. Usar un `slug` unico, en minusculas y con guiones.
5. No usar nombres de unidades reales si no han sido aprobados para una etapa posterior.

Ejemplo minimo de programa ficticio:

```json
{
	"id": "program-demo-example-sciences",
	"slug": "programa-ejemplo-demo",
	"name": "Programa Demostrativo de Ciencias Ejemplo",
	"abbreviation": "PCE-D",
	"description": "Carrera ficticia para pruebas del catalogo.",
	"unitType": "program",
	"parentUnitId": "school-demo-example-sciences",
	"status": "active"
}
```

## Agregar Un Plan Curricular

1. Editar `src/content/catalog/curricula.json`.
2. `academicUnitId` debe apuntar a un `AcademicUnit` existente con `unitType: "program"`.
3. `status` debe ser `active` o `historical`.
4. `effectivePeriod` puede ser un anio o rango, por ejemplo `2026-2029`.

## Agregar Un Curso

1. Editar `src/content/catalog/courses.json`.
2. Agregar solo datos propios del curso: codigo, slug, nombre, resumen, creditos, etiquetas y estado.
3. No agregar escuela, carrera, plan, ciclo recomendado ni prerrequisitos dentro de `Course`.
4. `slug` debe ser unico para `/courses/[slug]`.

Los componentes y paginas leeran automaticamente el curso por la capa `src/domain/catalog.ts`.

## Ubicar Un Curso En Un Plan

1. Editar `src/content/catalog/curriculum-courses.json`.
2. `curriculumId` debe apuntar a un plan existente.
3. `courseId` debe apuntar a un curso existente.
4. `recommendedCycle` expresa el ciclo solo dentro de ese plan.
5. `requirementType` debe ser `required` o `elective`.
6. Cada entrada en `prerequisiteCourseIds` debe apuntar a un curso existente y presente en el mismo plan.
7. No crear ciclos directos de prerrequisitos dentro del mismo plan.

Para representar un curso comun, no dupliques el curso. Crea otra relacion `CurriculumCourse` apuntando al mismo `courseId` desde otro `curriculumId`.

## Agregar Un Periodo Academico

1. Editar `src/content/catalog/academic-terms.json`.
2. Usar `id` con forma `YYYY-1` o `YYYY-2`, por ejemplo `2027-1`.
3. `year` y `period` deben coincidir con el `id`.

## Agregar Un Recurso

1. Editar `src/content/catalog/resources.json`.
2. `courseId` debe apuntar a un curso existente.
3. `academicTermId`, si existe, debe apuntar a un periodo existente.
4. `demo` debe ser `true`.
5. `fileAvailable` debe ser `false` hasta que exista almacenamiento configurado.
6. No agregar campos de URL, rutas a archivos, PDFs, TEX, ZIP, DOCX ni binarios.
7. Para `book-reference`, describir solo la referencia bibliografica ficticia; no enlazar ni almacenar libros.

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
