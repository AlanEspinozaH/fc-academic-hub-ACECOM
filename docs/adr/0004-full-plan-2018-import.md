# ADR 0004: Importacion completa de planes 2018

## Estado

Aceptada

## Contexto

El catalogo ficticio ya no era suficiente para validar busqueda, navegacion curricular y relaciones por plan. Existia un paquete normalizado de cinco CSV de planes de estudios 2018 con 386 cursos y 556 relaciones.

## Decision

Importar los cinco planes 2018 al catalogo estatico activo, manteniendo la separacion entre `Course` y `CurriculumCourse`.

Agregar `pending-verification` como estado de `Curriculum`, conservar `sourceUrl`, y ampliar `CurriculumCourse` con categoria curricular, ciclo nullable, prerrequisitos, Tipo, S.E., silabo, horas crudas y fuente de fila.

El filtro por ciclo requiere carrera porque el mismo curso puede tener ciclos distintos segun plan y los electivos no tienen ciclo fijo.

## Consecuencias

- El catalogo activo contiene 386 cursos, 556 relaciones, 5 curricula y 11 unidades academicas.
- Los planes permanecen pendientes de verificacion oficial de vigencia.
- Los silabos visibles se muestran como referencias a la fuente original, no como URLs inventadas.
- Supabase, PostgreSQL, autenticacion y R2 siguen fuera de alcance.

## Alternativas consideradas

- Guardar prerrequisitos en `Course`: rechazado porque varian por plan.
- Usar `typeCode` o `evaluationSystemCode` para inferir obligatoriedad: rechazado porque no hay fuente oficial para interpretar esas siglas.
- Marcar todos los planes como activos: rechazado porque su vigencia aun requiere verificacion.
