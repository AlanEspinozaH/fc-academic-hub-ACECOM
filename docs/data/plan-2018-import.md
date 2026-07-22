# Importacion de planes de estudios 2018

La importacion activa reemplaza el catalogo ficticio por los cinco planes de estudios 2018 de la Facultad de Ciencias.

## Paquete fuente

El staging revisable esta en `data/import/plan-2018/` y contiene:

- `academic-units.json`
- `curricula.json`
- `courses.json`
- `curriculum-courses.json`
- `normalization-report.json`
- `prerequisite-variants.json`
- `type-evaluation-variants.json`
- `courses.csv` y `curriculum-courses.csv` como vistas de revision humana

Los JSON normalizados son insumo de importacion. Los CSV no se transcriben manualmente en el catalogo activo.

## Conteos importados

- 386 cursos unicos.
- 556 relaciones curso-plan.
- 5 planes curriculares.
- 11 unidades academicas entre facultad, escuelas y programas.

Si una importacion futura no conserva esos conteos para este paquete, debe detenerse antes de copiar datos activos.

## Procedencia

Los registros provienen de cinco CSV exportados de planes 2018 con silabos visibles para:

- N1 Fisica.
- N2 Matematica.
- N3 Quimica.
- N5 Ingenieria Fisica.
- N6 Ciencia de la Computacion.

Cada `Curriculum` conserva `sourceUrl`. Cada `CurriculumCourse` conserva `source.file`, `source.row` y `source.curriculumUrl` para rastrear la fila original.

## Normalizacion aplicada

`Course` representa el curso estable por codigo: identidad, nombre, creditos, resumen, etiquetas, estado y escuela administradora cuando se pudo inferir por prefijo.

`CurriculumCourse` representa la ubicacion del curso dentro de un plan: ciclo recomendado, categoria de obligatoriedad, prerrequisitos, Tipo, S.E., silabo visible, horas crudas y fuente de la fila.

Los prerrequisitos no se movieron a `Course` porque un mismo codigo puede tener prerrequisitos distintos segun el plan.

## Categorias curriculares

`requirementType` admite exactamente:

- `required`: Obligatorio.
- `specialty-elective`: Electivo de especialidad.
- `complementary-elective`: Electivo complementario.

Los cursos obligatorios deben tener `recommendedCycle` entre 1 y 10. Los electivos quedan con `recommendedCycle: null` si no tienen ciclo fijo.

## Tipo, S.E. y silabos

`typeCode` y `evaluationSystemCode` se conservan separados. No se interpretan sus siglas porque el paquete no incluye una fuente oficial para su significado.

Los CSV contienen etiquetas visibles de silabo, pero no las URLs reales de los hipervinculos. Por eso `syllabus.url` queda `null` y la UI enlaza al plan curricular original cuando existe etiqueta visible.

## Escuela administradora

La inferencia de administracion usa solo las reglas indicadas para prefijos:

- `CM` -> Escuela Profesional de Matematica, N2.
- `CF` -> Escuela Profesional de Fisica, N1.
- `IF` o `IFE` -> Escuela Profesional de Ingenieria Fisica, N5.
- `CQ` -> Escuela Profesional de Quimica, N3.
- `CC` -> Escuela Profesional de Ciencia de la Computacion, N6.

Los demas prefijos quedan con `adminAcademicUnitId: null` y `adminAssignmentBasis: pending-verification`.
