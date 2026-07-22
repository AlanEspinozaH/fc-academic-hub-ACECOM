# Paquete normalizado para FC Academic Hub

Este paquete se generó a partir de cinco CSV adjuntos de los planes de estudios 2018.

## Totales

- 386 cursos únicos.
- 556 relaciones curso-plan.
- 5 planes.
- 11 unidades académicas.
- 49 códigos con prerrequisitos distintos según plan.
- 32 códigos con valores distintos de Tipo o S.E.
- 0 prerrequisitos sin código de curso correspondiente.

## Archivos

- `academic-units.json`: facultad, escuelas y programas.
- `curricula.json`: los cinco planes 2018 y su URL fuente.
- `courses.json`: catálogo único por código.
- `curriculum-courses.json`: ciclo, obligatoriedad/electividad, prerrequisitos y datos de la fila fuente.
- `normalization-report.json`: métricas, conflictos y notas.
- `prerequisite-variants.json`: cursos cuyos prerrequisitos varían por plan.
- `type-evaluation-variants.json`: variaciones de `Tipo` y `S.E.`.
- `courses.csv` y `curriculum-courses.csv`: vistas para revisión humana.

## Advertencias

1. Los CSV contienen el texto visible del vínculo de sílabo, pero no la URL del hipervínculo.
2. `Tipo` y `S.E.` se conservaron como campos separados sin adjudicarles un significado no definido por las fuentes.
3. Los campos T, P, L y S se conservaron como texto crudo porque aparecen valores como `-2` y `-3`.
4. La escuela administradora solo se infirió para los prefijos indicados por el usuario: CM, CF, IF/IFE, CQ y CC.
5. Los planes se marcaron `pending-verification`; debe confirmarse si el Plan 2018 sigue vigente en cada programa.
6. El archivo de Física contiene notas de actualización posteriores, incluidas modificaciones aplicables desde 2025-1.

Este paquete es un insumo de importación y revisión. Codex debe adaptar el esquema del proyecto antes de copiarlo directamente.
