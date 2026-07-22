# Modelo De Datos Del Catalogo

## Alcance

El catalogo de etapa 2 es publico y estatico. La primera muestra migra codigos y nombres de cursos reales de Drive FC, pero todavia no almacena documentos reales, datos personales, URLs de descarga, libros digitales, autenticacion, roles, Supabase, PostgreSQL ni R2.

Los registros viven en `src/content/catalog/*.json` y son validados por `src/content.config.ts` y por pruebas de integridad de dominio. Los creditos, ciclos y prerrequisitos que no esten respaldados por una fuente disponible deben quedar marcados como pendientes de verificacion.

## Entidades

### AcademicUnit

Representa la jerarquia academica visible para organizar planes y carreras en la muestra inicial.

- `id`: identificador estable y unico.
- `slug`: identificador legible para rutas o filtros.
- `name`: nombre publico visible.
- `abbreviation`: abreviatura visible.
- `description`: descripcion editorial.
- `unitType`: `faculty`, `school` o `program`.
- `parentUnitId`: unidad padre, ausente solo en facultades.
- `status`: `active` o `inactive`.

Las rutas `/schools` muestran unidades con `unitType: "school"`.

### Curriculum

Representa una version concreta del plan de estudios de un programa.

- `id`: identificador estable y unico.
- `code`: codigo visible del plan, por ejemplo `N6`.
- `name`: nombre del plan.
- `academicUnitId`: referencia a un `AcademicUnit.id` con `unitType: "program"`.
- `effectivePeriod`: periodo de vigencia o `pending-verification` si aun no fue contrastado.
- `status`: `active` o `historical`.

### Course

Representa un curso estable, sin pertenencia curricular intrinseca.

- `id`: identificador estable y unico con forma `course:<codigo-en-minusculas>`.
- `code`: codigo visible del curso en mayusculas.
- `slug`: identificador para `/courses/[slug]`; debe iniciar con el codigo en minusculas seguido de guion.
- `name`: nombre del curso.
- `summary`: resumen editorial del registro.
- `credits`: creditos enteros positivos o `null` cuando no esten verificados.
- `dataStatus`: `pending-verification` cuando el registro contiene datos obligatorios pendientes, actualmente creditos desconocidos.
- `tags`: etiquetas publicas.
- `status`: `active` o `historical`.

`Course` no contiene escuela, carrera, plan, ciclo recomendado ni prerrequisitos. Esos datos dependen de cada plan curricular.

### CurriculumCourse

Relaciona un curso con una version concreta de plan de estudios.

- `id`: identificador estable de la relacion con forma `curriculum-course:<plan>:<codigo-en-minusculas>`.
- `curriculumId`: referencia a `Curriculum.id`.
- `courseId`: referencia a `Course.id`.
- `recommendedCycle`: ciclo recomendado dentro de ese plan.
- `requirementType`: `required`, `elective` o `pending-verification`.
- `prerequisiteCourseIds`: referencias a `Course.id` usadas como prerrequisitos dentro del mismo plan.

Un curso comun de primer ciclo se modela con un solo registro en `courses.json` y varias relaciones en `curriculum-courses.json`, una por plan.

### AcademicTerm

Representa periodos como `2026-1` y `2026-2`.

- `id`: debe cumplir `YYYY-1` o `YYYY-2`.
- `label`: etiqueta visible.
- `year`: anio numerico.
- `period`: `1` o `2`, coherente con el `id`.

### AcademicResource

Representa metadatos de recursos academicos. En etapa 2 no representa archivos descargables y puede permanecer vacio hasta que existan recursos verificados.

- `id`: identificador estable y unico.
- `slug`: slug unico del recurso.
- `title`: titulo visible.
- `description`: descripcion editorial.
- `resourceType`: uno de los tipos iniciales.
- `courseId`: referencia a `Course.id`.
- `academicTermId`: referencia opcional a `AcademicTerm.id`.
- `evaluation`: etiqueta opcional de evaluacion.
- `hasSolution`: indica si el recurso tiene solucion registrada conceptualmente.
- `reviewStatus`: estado editorial.
- `visibility`: `public` o `restricted`.
- `rightsStatus`: estado de derechos.
- `language`: codigo de idioma.
- `tags`: etiquetas publicas.
- `demo`: debe ser `true` mientras el recurso sea demostrativo.
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
- codigos de curso duplicados;
- convencion de `Course.id`, `Course.code` y prefijo de `Course.slug`;
- cursos con creditos pendientes sin `dataStatus`;
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
