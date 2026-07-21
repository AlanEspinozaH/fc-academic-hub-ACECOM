# Modelo De Datos Del Catalogo

## Alcance

El catalogo de etapa 2 es publico, estatico y ficticio. Los registros viven en `src/content/catalog/*.json` y son validados por `src/content.config.ts` y por pruebas de integridad de dominio.

No contiene documentos reales, datos personales, URLs de descarga, libros digitales, autenticacion, roles, Supabase, PostgreSQL ni R2.

## Entidades

### AcademicUnit

Representa la jerarquia academica demo: facultad, escuelas y programas.

- `id`: identificador estable y unico.
- `slug`: identificador legible para rutas o filtros.
- `name`: nombre publico ficticio.
- `abbreviation`: abreviatura visible.
- `description`: descripcion ficticia.
- `unitType`: `faculty`, `school` o `program`.
- `parentUnitId`: unidad padre, ausente solo en facultades.
- `status`: `active` o `inactive`.

En los datos demo, los programas representan carreras ficticias. Las rutas `/schools` muestran unidades con `unitType: "school"`.

### Curriculum

Representa una version concreta del plan de estudios de un programa.

- `id`: identificador estable y unico.
- `code`: codigo visible del plan.
- `name`: nombre del plan.
- `academicUnitId`: referencia a un `AcademicUnit.id` con `unitType: "program"`.
- `effectivePeriod`: periodo de vigencia, por ejemplo `2026-2029`.
- `status`: `active` o `historical`.

### Course

Representa un curso estable, sin pertenencia curricular intrinseca.

- `id`: identificador estable y unico.
- `code`: codigo visible del curso.
- `slug`: identificador para `/courses/[slug]`.
- `name`: nombre del curso.
- `summary`: resumen ficticio.
- `credits`: creditos enteros positivos.
- `tags`: etiquetas publicas.
- `status`: `active` o `historical`.

`Course` no contiene escuela, carrera, plan, ciclo recomendado ni prerrequisitos. Esos datos dependen de cada plan curricular.

### CurriculumCourse

Relaciona un curso con una version concreta de plan de estudios.

- `id`: identificador estable y unico de la relacion.
- `curriculumId`: referencia a `Curriculum.id`.
- `courseId`: referencia a `Course.id`.
- `recommendedCycle`: ciclo recomendado dentro de ese plan.
- `requirementType`: `required` o `elective`.
- `prerequisiteCourseIds`: referencias a `Course.id` usadas como prerrequisitos dentro del mismo plan.

Un curso comun de primer ciclo se modela con un solo registro en `courses.json` y varias relaciones en `curriculum-courses.json`, una por plan.

### AcademicTerm

Representa periodos como `2026-1` y `2026-2`.

- `id`: debe cumplir `YYYY-1` o `YYYY-2`.
- `label`: etiqueta visible.
- `year`: anio numerico.
- `period`: `1` o `2`, coherente con el `id`.

### AcademicResource

Representa metadatos de recursos academicos. En etapa 2 no representa archivos descargables.

- `id`: identificador estable y unico.
- `slug`: slug unico del recurso.
- `title`: titulo visible.
- `description`: descripcion ficticia.
- `resourceType`: uno de los tipos iniciales.
- `courseId`: referencia a `Course.id`.
- `academicTermId`: referencia opcional a `AcademicTerm.id`.
- `evaluation`: etiqueta opcional de evaluacion ficticia.
- `hasSolution`: indica si el recurso tiene solucion registrada conceptualmente.
- `reviewStatus`: estado editorial.
- `visibility`: `public` o `restricted`.
- `rightsStatus`: estado de derechos demo.
- `language`: codigo de idioma.
- `tags`: etiquetas publicas.
- `demo`: debe ser `true` en etapa 2.
- `fileAvailable`: debe ser `false` mientras no exista storage configurado.

Tipos iniciales de recurso:

- `syllabus`
- `exam`
- `solution`
- `notes`
- `assignment`
- `laboratory`
- `class-material`
- `book-reference`

`book-reference` es solo una referencia bibliografica. No debe apuntar a un PDF ni a un libro digital.

## Integridad

`src/domain/catalog-integrity.ts` valida:

- identificadores duplicados;
- slugs duplicados;
- unidades academicas con padres inexistentes o tipos de padre incorrectos;
- planes con unidades academicas inexistentes o no programaticas;
- relaciones curriculum-curso duplicadas;
- relaciones con planes, cursos o prerrequisitos inexistentes;
- prerrequisitos fuera del mismo plan curricular;
- referencias circulares directas de prerrequisitos dentro de un plan;
- terminos academicos invalidos o incoherentes;
- recursos con cursos inexistentes;
- recursos demo con URLs o referencias a archivos;
- recursos `fileAvailable` sin storage configurado;
- referencias bibliograficas marcadas con archivo disponible.

Las paginas leen el catalogo por `src/domain/catalog.ts`, que ejecuta la validacion y construye vistas derivadas para la UI. Las pruebas unitarias tambien ejecutan las validaciones sobre los JSON.
