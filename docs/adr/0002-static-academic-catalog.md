# ADR 0002: Catalogo Academico Estatico

## Estado

Aceptada

## Contexto

La etapa 2 necesita un catalogo academico publico para escuelas, planes, cursos y recursos sin introducir Supabase, PostgreSQL, autenticacion, R2 ni documentos reales. El catalogo debe ser barato de operar y facil de revisar por Git mientras prepara una futura migracion a PostgreSQL.

Astro 7.1.3 esta instalado. Los tipos locales exponen `src/content.config.ts`, `defineCollection`, `getCollection` y loaders desde `astro/loaders`.

## Decision

Usar Content Collections con loader `file()` y datos JSON versionados en `src/content/catalog/`.

Crear una capa de consulta en `src/domain/catalog.ts` para que paginas y componentes consuman tipos de dominio, no detalles de almacenamiento. La capa valida integridad con `src/domain/catalog-integrity.ts` antes de retornar datos.

Prerenderizar paginas sin filtros dinamicos cuando sea posible:

- `/`, `/schools`, `/schools/[slug]` y `/courses/[slug]` se prerenderizan.
- `/courses` y `/resources` permanecen renderizadas bajo demanda porque sus filtros usan query params y deben funcionar sin JavaScript.

Mantener todos los recursos demo sin archivos, sin URLs de descarga y con `fileAvailable: false` hasta que exista almacenamiento privado configurado.

## Cloudflare SESSION/KV

Al ejecutar `astro check`, el adaptador `@astrojs/cloudflare@14.1.4` muestra:

```text
Enabling sessions with Cloudflare KV with the "SESSION" KV binding.
```

La auditoria local encontro que el adaptador agrega por defecto un driver de sesiones basado en Cloudflare KV cuando `astro.config.mjs` no define `config.session.driver`. La opcion tipada disponible es cambiar `sessionKVBindingName`; no hay una opcion tipada para desactivar esa configuracion por completo.

En etapa 2 no usamos `Astro.session`, no agregamos `kv_namespaces` a `wrangler.jsonc`, no creamos namespaces KV y no desplegamos. Si se despliega con esta version del adaptador, Cloudflare/Wrangler podria requerir o autoprovisionar el binding `SESSION` para sesiones aunque la aplicacion no lo use directamente. Antes de desplegar una etapa futura se debe decidir explicitamente si se usaran sesiones Astro con KV o si se actualizara/configurara el adaptador para evitar ese binding.

No se inventan IDs ni bindings de Cloudflare en esta etapa.

Ademas, `astro.config.mjs` fija `prerenderEnvironment: 'node'` en el adaptador Cloudflare. El build local con el prerender por defecto `workerd` fallo al procesar un binding reservado `ASSETS` para Pages; las rutas prerenderizadas de etapa 2 solo leen contenido estatico y no usan APIs Cloudflare, por lo que prerenderizar en Node evita ese fallo sin cambiar el runtime server ni crear recursos cloud.

## Consecuencias

- El catalogo es revisable por PR y no requiere base de datos.
- Las validaciones cruzadas fallan en pruebas y durante lectura del catalogo para build/prerender.
- La migracion futura a PostgreSQL puede reemplazar `src/domain/catalog.ts` sin reescribir componentes visuales.
- Los filtros de `/courses` y `/resources` generan invocaciones futuras de Worker porque priorizan accesibilidad sin JavaScript.

## Alternativas Consideradas

- Datos TypeScript en `src/domain/`: rechazado porque Content Collections dan esquemas y una ruta natural para contenido versionado.
- Filtrado solo con JavaScript en paginas prerenderizadas: rechazado porque los filtros deben seguir funcionando con JavaScript desactivado.
- Supabase/PostgreSQL en etapa 2: rechazado por restriccion explicita de la etapa.
- Configurar un KV `SESSION` manualmente: rechazado porque no se deben crear ni inventar recursos Cloudflare en etapa 2.
