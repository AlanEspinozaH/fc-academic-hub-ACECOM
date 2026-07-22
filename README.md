# FC Academic Hub

FC Academic Hub es la base de una plataforma academica comunitaria de la Facultad de Ciencias. El objetivo es organizar cursos, examenes, apuntes, silabos y recursos relacionados con seguridad y bajo costo operativo.

La etapa actual mantiene un catalogo academico publico y estatico con los cinco planes de estudios 2018 importados desde un paquete normalizado. La etapa 3B.2B conecta Google OAuth con un proyecto Supabase remoto, valida el dominio institucional en PostgreSQL y mantiene sesiones SSR en desarrollo local. Las credenciales reales permanecen fuera de Git. Todavia no existen rutas privadas, proteccion del catalogo, subida de documentos, integracion con Cloudflare R2 ni despliegue publico.

## Alcance actual

- Astro con TypeScript estricto.
- Adaptador de Cloudflare configurado para un futuro despliegue en Pages/Workers, con `output: 'server'`.
- Content Collections con datos JSON versionados en Git.
- Catalogo activo con 386 cursos, 556 relaciones curso-plan, 5 planes curriculares y 11 unidades academicas.
- Capa de consulta en `src/domain/catalog.ts` para aislar paginas y componentes del almacenamiento.
- Validaciones de integridad para duplicados, relaciones cruzadas, prerrequisitos, ciclos, silabos, fuentes y restricciones de storage.
- Paginas publicas para `/`, `/schools`, `/schools/[slug]`, `/courses`, `/courses/[slug]`, `/resources`, `/about` y 404.
- Endpoint JSON GET `/api/health` con version tomada de `package.json`.
- Migraciones locales de Supabase/PostgreSQL para RBAC, dominios de correo, perfiles, auditoria, RLS y sincronizacion Auth -> profiles.
- Matriz TypeScript explicita de roles y permisos en `src/domain/auth/`.
- Configuracion validada de `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- Fabricas Supabase SSR en `src/infrastructure/supabase/` para navegador y servidor, sin ejecutar login ni consultas al importar.
- Middleware SSR que valida identidad con `auth.getUser()` por request y expone `Astro.locals.auth` sin tokens ni roles.
- Triggers PostgreSQL que validan dominios institucionales exactos en `auth.users` y crean/sincronizan `public.profiles` sin asignar roles.
- Pagina GET `/auth/sign-in`, endpoint POST `/auth/google`, callback GET `/auth/callback` y endpoint POST `/auth/sign-out` conectados con Google OAuth y Supabase remoto mediante configuracion privada externa al repositorio.
- Redaccion previa de `provider_token` y `provider_refresh_token` en respuestas del endpoint Supabase Auth de intercambio de token, antes de que `auth-js` procese y persista la sesion.

## Requisitos

- Node.js >=22.12.0.
- npm con instalacion basada en lockfile.

## Instalacion

```sh
npm ci
npm run dev
```

Variables locales para Supabase:

```sh
cp .env.example .env.local
```

Reemplazar solo `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY` en `.env.local`. La publishable key puede llegar al navegador; las llaves secretas, passwords de base de datos, JWT secrets y credenciales remotas no deben versionarse ni usarse en el runtime de Astro. La proteccion real de datos depende de RLS y de autorizacion validada en servidor.

Supabase local para pruebas de base de datos:

```sh
npx --yes supabase@2.109.1 start
npx --yes supabase@2.109.1 db reset
npx --yes supabase@2.109.1 test db
npx --yes supabase@2.109.1 db lint --local
npx --yes supabase@2.109.1 stop
```

La CLI validada para 3B.2B es Supabase CLI 2.109.1. Los comandos `login`, `link` y `db push` solo deben ejecutarse de forma intencional, verificando antes el proyecto remoto y revisando `db push --dry-run`.

## Controles de calidad

Ejecutar el pipeline local completo:

```sh
npm run ci
```

Controles individuales:

```sh
npm run format:check
npm run lint
npm run check
npm run test
npm run build
```

El script `npm run deploy` queda reservado para un flujo futuro con autorizacion explicita. No desplegar sin aprobacion.

## Estructura

```text
src/
  components/       Componentes Astro reutilizables.
  config/           Configuracion general del sitio.
  content/          Datos activos del catalogo versionados en Git.
  domain/           Tipos, filtros, consultas y validaciones del catalogo; matriz auth local.
  infrastructure/   Helpers de servidor, health y fabricas de clientes Supabase.
  layouts/          Shell compartido del documento y estilos globales.
  pages/            Rutas Astro y endpoints API.
data/
  import/           Paquetes staging usados para importaciones revisables.
docs/
  adr/              Registros de decision arquitectonica.
  architecture/     Documentos de arquitectura.
  operations/       Procedimientos operativos sin secretos.
  data/             Modelo y guias para contenido del catalogo.
  security/         Modelo de roles, bootstrap administrativo y riesgos aceptados.
supabase/
  migrations/       Migraciones PostgreSQL reproducibles.
  tests/database/   Pruebas pgTAP de RLS y autorizacion.
```

## Agregar contenido

Los registros activos se agregan editando JSON en `src/content/catalog/`, no componentes. Ver `docs/data/catalog-model.md`, `docs/data/adding-catalog-content.md` y `docs/data/plan-2018-import.md` antes de cambiar datos.

## Limites vigentes

- No crear paginas privadas ni usar `Astro.locals.auth` para bloquear rutas del catalogo todavia.
- No cambiar el proyecto Supabase remoto vinculado ni aplicar migraciones sin verificar `projects list`, `migration list` y `db push --dry-run`.
- No almacenar Client Secret de Google, tokens CLI, contrasenas, cookies ni claves secretas en Git, `.env.local`, documentacion o capturas.
- No crear buckets, namespaces ni bindings Cloudflare nuevos.
- No implementar proteccion de rutas, administracion de roles ni autenticacion ficticia.
- No asignar roles ni crear administradores automaticamente al crear perfiles.
- No solicitar scopes ni almacenar `provider_token` o `provider_refresh_token` de Google.
- No implementar formularios de subida.
- No almacenar documentos, PDFs, TEX, binarios, libros comerciales ni registros reales de recursos.
- No commitear secretos. Mantener archivos `.env*` ignorados excepto `.env.example`; los valores reales van en `.env.local`.
- No desplegar sin autorizacion explicita.

## Cloudflare SESSION/KV

Con `@astrojs/cloudflare@14.1.4`, Astro muestra que habilita sesiones con KV `SESSION` si no hay driver de sesion configurado. FC Academic Hub no usa sesiones de Astro en esta etapa y `wrangler.jsonc` no declara KV. La decision esta documentada en `docs/adr/0002-static-academic-catalog.md` y debe revisarse antes de desplegar una etapa futura.
