# Autenticacion y autorizacion

La etapa 3B.2A agrega el flujo de aplicacion para Google OAuth con PKCE sobre las fabricas Supabase de 3A.2A, el middleware SSR de 3A.2B y el ciclo de vida PostgreSQL Auth/profiles de 3B.1. No configura todavia credenciales reales de Google, proyecto Supabase remoto, paginas privadas, proteccion de rutas ni administracion de roles. Tampoco mueve el catalogo academico fuera de `src/content/catalog/`.

## Separacion de responsabilidades

Autenticacion responde quien es el usuario. El middleware SSR de 3A.2B valida la identidad con `supabase.auth.getUser()` por request y expone un contexto minimo en `Astro.locals.auth`. La etapa 3B.1 sincroniza `auth.users` con `public.profiles` mediante triggers PostgreSQL. La etapa 3B.2A agrega pagina de acceso, inicio OAuth por POST, callback de aplicacion y logout por POST, sin proteger rutas del catalogo todavia.

Autorizacion responde que puede hacer ese usuario. PostgreSQL es la fuente autoritativa para roles: `public.user_roles` conserva asignaciones historicas, las funciones de autorizacion consultan asignaciones activas con `auth.uid()`, y las politicas RLS se evaluan en el servidor.

## Decisiones de seguridad

La configuracion publica de Supabase se limita a `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY`. La publishable key puede estar disponible en el navegador porque identifica el proyecto y opera bajo las reglas de Auth, permisos y RLS; no reemplaza autorizacion del servidor ni concede privilegios administrativos. Las llaves secretas quedan fuera de Astro y no se declaran en `.env.example`.

Los roles no se guardan en `localStorage` ni en estado enviado por el navegador. Cualquier dato controlado por el cliente puede manipularse, por lo que la autoridad vive en PostgreSQL y se consulta del lado servidor.

La aplicacion no usa la llave `service_role`. Esa llave omite RLS y queda reservada para tareas administrativas fuera del runtime de Astro. Las funciones `SECURITY DEFINER` tienen `search_path` explicito, no usan SQL dinamico y limitan `EXECUTE`.

No se implementan custom JWT claims todavia. Duplicar roles en claims adelanta problemas de invalidacion y revocacion; los roles activos deben seguir resolviendose desde PostgreSQL en cada decision de autorizacion. Si una etapa futura necesita claims por rendimiento, debera registrar un ADR y definir invalidacion segura.

## Flujo Google OAuth 3B.2A

`/auth/sign-in` es una pagina GET que muestra un unico formulario para continuar con Google. Acepta `next` solo como destino interno validado y muestra mensajes genericos mediante codigos controlados. Si el usuario ya esta autenticado, redirige a `next` despues de aplicar la misma validacion segura.

`/auth/google` acepta solo POST. Valida `Origin` cuando esta presente, evita reiniciar OAuth para usuarios ya autenticados, usa `Astro.locals.auth.supabase`, valida `next`, construye `redirectTo` con el origin efectivo de la request y `/auth/callback`, y llama a `auth.signInWithOAuth({ provider: 'google', options: { redirectTo } })`. La URL de autorizacion la devuelve Supabase Auth; la aplicacion no construye URLs de Google ni solicita scopes para Drive, Calendar, Gmail u otras APIs.

`/auth/callback` acepta solo GET. Procesa `code`, maneja `error` y `error_description` sin reflejar valores no confiables, valida `next`, ejecuta `auth.exchangeCodeForSession(code)` y luego valida identidad mediante `auth.getUser()`. No usa `getSession()` como autoridad, no lee roles desde metadata y siempre elimina `code` y errores de proveedor mediante una redireccion final. Si el intercambio establece una sesion pero la validacion posterior falla, limpia la sesion local de forma best-effort.

`/auth/sign-out` acepta solo POST. Valida `Origin` cuando esta presente, ignora identificadores o tokens enviados por formulario, ejecuta `auth.signOut({ scope: 'local' })` y redirige con 303 a un destino interno seguro. El logout es idempotente cuando la sesion ya no existe.

Los destinos posteriores a autenticacion se validan de forma separada de una redireccion interna general: `/auth` y sus subrutas se rechazan para evitar bucles o reentrada en el flujo.

Hay dos callbacks distintos:

1. Google -> Supabase Auth: callback administrada por Supabase Auth y configurada en Google/Supabase durante 3B.2B.
2. Supabase Auth -> aplicacion Astro: `/auth/callback`, implementada en 3B.2A para completar el intercambio PKCE en el cliente SSR.

La configuracion real del proveedor Google, credenciales y allow-list remota de redirects pertenecen a 3B.2B.

## Recursos academicos 4A

La etapa 4A agrega metadatos de recursos academicos a PostgreSQL sin mover el catalogo de cursos fuera de JSON y sin crear R2. `public.academic_resources` guarda metadatos revisables; `public.resource_files` guarda metadatos no sensibles de archivos; `private.resource_storage_objects` guarda `storage_key` y estado interno; `public.resource_review_events` registra eventos append-only.

Las RLS usan perfiles activos y roles activos. `anon` solo lee recursos aprobados publicos. Usuarios autenticados activos pueden leer aprobados restringidos. Propietarios con rol `contributor` o superior crean y editan recursos propios en `draft` o `rejected`; `reviewer` rechaza pero no publica; `moderator` y `administrator` aprueban/publican. Las transiciones se hacen por RPC transaccionales, no por cambios directos de estado.

`course_id` y `academic_term_id` son referencias logicas al catalogo JSON hasta una migracion futura del catalogo a PostgreSQL. 4A no crea URLs publicas ni buckets R2; la subida binaria pertenece a 4B y la revision/descarga a 4C.

## Tratamiento de tokens del proveedor

Supabase puede devolver `provider_token` y `provider_refresh_token` con la sesion OAuth. `auth-js` persiste la sesion adquirida en el almacenamiento configurado, por lo que omitir esos campos en la logica posterior al intercambio no es suficiente.

`src/infrastructure/supabase/provider-token-redaction.ts` envuelve el `fetch` usado por las fabricas server y browser. Solo para respuestas exitosas y JSON del endpoint exacto `/auth/v1/token` del origin Supabase configurado, elimina recursivamente `provider_token` y `provider_refresh_token` antes de entregar la respuesta a `auth-js`. Los tokens propios de Supabase se conservan.

La redaccion se realiza antes de la persistencia. No se confia en opciones de serializacion de cookies para eliminar campos de la sesion.

## Clientes SSR

`src/infrastructure/supabase/config.ts` valida entorno sin imprimir valores. `browser.ts` crea el cliente de navegador de forma lazy con `createBrowserClient` y reutiliza una instancia solo en runtime de navegador. `server.ts` crea un cliente nuevo por request con `createServerClient`, recibe `Request`, `AstroCookies` y `Headers` explicitamente, y adapta cookies con `getAll`/`setAll`.

Ambas fabricas inyectan el adaptador de redaccion de tokens del proveedor. No llaman `getSession`, `getUser`, `getClaims`, login, logout ni consultas durante import. El middleware llama `getUser()` solo durante la request, interpreta la falta de sesion como `anonymous`, propaga `Set-Cookie`, `Cache-Control` y `Pragma`, y deja `unconfigured` cuando falta entorno Supabase. No usa `getSession()` como autoridad ni expone tokens, sesion completa, claves o roles en `Astro.locals`.

El adaptador continua siendo `@astrojs/cloudflare` con `output: 'server'`; no se agrega otro runtime.

## Contexto de sesion SSR

`Astro.locals.auth` contiene `status`, `user` y `supabase`. Los estados posibles son `unconfigured`, `anonymous`, `authenticated` y `error`. El usuario local solo contiene `id` y `email`; cuando no hay usuario validado es `null`. El cliente `supabase` es el cliente server por request o `null` si la configuracion no esta disponible.

Este contexto no autoriza rutas por si solo. Las decisiones de autorizacion futuras deben ejecutarse en servidor y mantener PostgreSQL como autoridad de roles mediante RLS y funciones controladas.

## Ciclo de vida Auth/profiles

`auth.users` es la identidad administrada por Supabase. `public.profiles` contiene datos de aplicacion: `user_id`, email normalizado, nombre visible y estado de cuenta. PostgreSQL valida el dominio completo del email contra `public.allowed_email_domains` antes de insertar o cambiar `auth.users.email`; un valor invalido hace rollback de la operacion.

Despues de crear un usuario Auth valido, un trigger crea el perfil con `display_name = null` y `account_status = active`. Despues de cambiar el email, solo sincroniza `profiles.email` y `profiles.updated_at`; no toca nombre visible, estado, roles ni auditoria. Una migracion correctiva agrega `private.reconcile_auth_user_profiles()` para perfiles preexistentes: recrea perfiles faltantes, corrige emails obsoletos, preserva `display_name`, `account_status` y `created_at`, y aborta sin cambios parciales si un email ya pertenece al perfil de otro `user_id`. La eliminacion del perfil sigue el `ON DELETE CASCADE` existente.

No se copian automaticamente `raw_user_meta_data`, `app_metadata`, proveedor OAuth, avatar, tokens ni informacion de Google. No se asigna `student` ni ningun otro rol, y no existe administrador automatico. Google OAuth no reemplaza la validacion de dominio institucional: un hook remoto Before User Created puede agregarse despues como validacion anticipada, pero no reemplaza los triggers PostgreSQL.

## Entorno local

Supabase local se configura en `supabase/config.toml`. La CLI probada para esta etapa fue `supabase 2.109.1` via `npx --yes supabase@2.109.1`. El entorno local no debe exponerse a Internet.

Comandos locales:

```sh
npx --yes supabase@2.109.1 start
npx --yes supabase@2.109.1 db reset
npx --yes supabase@2.109.1 test db
npx --yes supabase@2.109.1 db lint --local
npx --yes supabase@2.109.1 stop
```

No usar `supabase login`, `supabase link`, `db push` ni variantes `--linked` para esta etapa.
