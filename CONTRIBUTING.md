# Contribuir

## Flujo De Desarrollo

- Trabajar en ramas de feature, no directamente en main.
- Mantener cambios acotados y alineados con los limites de la etapa actual.
- Preferir tipos de dominio y componentes pequenos sobre logica improvisada dentro de paginas.
- No agregar dependencias sin documentar por que son necesarias.
- No hacer commit, push ni despliegue sin que el flujo de trabajo lo solicite explicitamente.

## Catalogo Academico

El catalogo de etapa 2 se modifica editando `src/content/catalog/*.json`.

- No modificar componentes para agregar una unidad academica, curso, plan, relacion curricular, periodo o recurso.
- Registrar datos reales solo con fuente documentada; mantener placeholders claramente marcados como pendientes.
- No agregar docentes reales, evaluaciones reales, datos personales, documentos, URLs de descarga ni binarios.
- No agregar ciclo recomendado, plan, escuela ni prerrequisitos dentro de `Course`; usar `CurriculumCourse`.
- Mantener `fileAvailable: false` mientras no exista storage configurado.
- Usar `book-reference` solo como referencia bibliografica, nunca como archivo de libro.
- Leer `docs/data/catalog-model.md` y `docs/data/adding-catalog-content.md` antes de cambiar datos.

## Supabase Local

Las migraciones y pruebas de base de datos viven en `supabase/`. Usar solamente el flujo local:

```sh
npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
npx --yes supabase@latest db lint --local
npx --yes supabase@latest stop
```

No usar `supabase login`, `supabase link`, `db push`, proyectos remotos ni variantes `--linked` para trabajos de etapa 3A.

## Controles Locales

Antes de abrir un pull request, ejecutar:

```sh
npm run ci
```

Este comando ejecuta formato, lint, chequeo de Astro/TypeScript, pruebas unitarias y build de produccion.

## Datos Y Seguridad

- No agregar secretos, tokens, passwords ni credenciales reales.
- No agregar datos personales.
- No agregar documentos academicos reales.
- No confiar en roles enviados por el navegador en trabajos futuros de autorizacion.
- Mantener archivos `.env*` ignorados excepto `.env.example`.
- No crear recursos Cloudflare, proyectos Supabase remotos ni R2 desde cambios de codigo.
- No conectar clientes Supabase a paginas Astro hasta una etapa aprobada para autenticacion.

## Documentacion

Actualizar README o docs cuando cambien comportamiento, arquitectura o setup. Las decisiones arquitectonicas importantes deben registrarse en `docs/adr/`.
