# Agregar o actualizar contenido del catalogo

Antes de cambiar datos, leer `docs/data/catalog-model.md` y ejecutar `npm run ci` al finalizar.

## Reglas generales

- Editar `src/content/catalog/*.json`, no componentes visuales.
- No agregar secretos, datos personales, documentos, PDFs, TEX ni URLs de descarga.
- Mantener `Course` separado de `CurriculumCourse`.
- Conservar fuentes: `Curriculum.sourceUrl` y `CurriculumCourse.source`.
- No inventar resumenes ni silabos. Usar `summary: null` o `syllabus.url: null` cuando falte fuente oficial.

## Actualizar un plan futuro

No sobrescribir el Plan 2018. Crear nuevos `Curriculum` con otro `effectivePeriod` y nuevas relaciones `CurriculumCourse` para ese plan.

Si un curso conserva codigo y creditos, reutilizar el mismo `Course`. Si cambia el credito por codigo, detenerse y documentar la discrepancia antes de importar.

## Ciclos y filtros

El ciclo depende de una carrera y un plan. Por eso `/courses?cycle=...` sin `program` se ignora y la UI pide seleccionar primero una carrera.

## Categorias

Usar solo:

- `required`
- `specialty-elective`
- `complementary-elective`

No derivar la categoria desde `typeCode` ni desde `evaluationSystemCode`.
