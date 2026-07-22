# Modelo del catalogo academico

El catalogo activo vive en `src/content/catalog/*.json` y se valida con Content Collections, tipos de dominio y pruebas de integridad.

## AcademicUnit

Representa facultad, escuelas y programas.

Campos principales: `id`, `slug`, `name`, `abbreviation`, `description`, `unitType`, `parentUnitId` y `status`.

`description` puede ser `null` cuando la fuente oficial no contiene una descripcion confiable.

## Curriculum

Representa una version concreta de plan de estudios para un programa.

Campos: `id`, `code`, `name`, `academicUnitId`, `effectivePeriod`, `status` y `sourceUrl`.

Los planes 2018 importados estan en `pending-verification` hasta confirmar oficialmente su vigencia.

## Course

Representa el curso estable por codigo.

Campos: `id`, `code`, `slug`, `name`, `credits`, `summary`, `adminAcademicUnitId`, `adminAssignmentBasis`, `tags` y `status`.

No contiene ciclo, categoria curricular ni prerrequisitos. Esos campos dependen del plan.

## CurriculumCourse

Relaciona un curso con un plan curricular.

Campos: `id`, `curriculumId`, `courseId`, `requirementType`, `recommendedCycle`, `prerequisiteCourseIds`, `typeCode`, `evaluationSystemCode`, `syllabus`, `hours` y `source`.

`recommendedCycle` es obligatorio para `required` y `null` para `specialty-elective` y `complementary-elective` cuando no hay ciclo fijo.

`typeCode` y `evaluationSystemCode` son codigos de fuente separados. No se usan para decidir obligatoriedad.

## Recursos

`resources.json` queda temporalmente vacio porque los recursos demo anteriores apuntaban al catalogo ficticio. No hay documentos reales, URLs de descarga ni archivos binarios en esta etapa.
