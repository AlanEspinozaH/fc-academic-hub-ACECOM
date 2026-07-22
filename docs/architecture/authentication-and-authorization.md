# Autenticacion y autorizacion

La etapa 3B.1 agrega el ciclo de vida PostgreSQL entre Supabase Auth y `public.profiles` sobre las fabricas Supabase de 3A.2A, el middleware SSR de 3A.2B y los fundamentos locales de PostgreSQL de 3A.1. No implementa login visible, Google OAuth, endpoints de callback, rutas logout, paginas privadas, proteccion de rutas ni administracion de roles. Tampoco mueve el catalogo academico fuera de `src/content/catalog/`.

## Separacion de responsabilidades

Autenticacion responde quien es el usuario. El middleware SSR de 3A.2B valida la identidad con `supabase.auth.getUser()` por request y expone un contexto minimo en `Astro.locals.auth`. La etapa 3B.1 sincroniza `auth.users` con `public.profiles` mediante triggers PostgreSQL. No hay pantallas de ingreso, Google OAuth, callback, logout ni proteccion de rutas; eso queda para etapas posteriores.

Autorizacion responde que puede hacer ese usuario. PostgreSQL es la fuente autoritativa para roles: `public.user_roles` conserva asignaciones historicas, las funciones de autorizacion consultan asignaciones activas con `auth.uid()`, y las politicas RLS se evaluan en el servidor.

## Decisiones de seguridad

La configuracion publica de Supabase se limita a `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY`. La publishable key puede estar disponible en el navegador porque identifica el proyecto y opera bajo las reglas de Auth, permisos y RLS; no reemplaza autorizacion del servidor ni concede privilegios administrativos. Las llaves secretas quedan fuera de Astro y no se declaran en `.env.example`.

Los roles no se guardan en `localStorage` ni en estado enviado por el navegador. Cualquier dato controlado por el cliente puede manipularse, por lo que la autoridad vive en PostgreSQL y se consulta del lado servidor.

La aplicacion no usa la llave `service_role`. Esa llave omite RLS y queda reservada para tareas administrativas fuera del runtime de Astro. Las funciones `SECURITY DEFINER` creadas en esta etapa tienen `search_path` explicito, no usan SQL dinamico y solo conceden `EXECUTE` a `authenticated` cuando hace falta.

No se implementan custom JWT claims todavia. Duplicar roles en claims adelanta problemas de invalidacion y revocacion; los roles activos deben seguir resolviendose desde PostgreSQL en cada decision de autorizacion. Si una etapa futura necesita claims por rendimiento, debera registrar un ADR y definir invalidacion segura.

## Clientes SSR

`src/infrastructure/supabase/config.ts` valida entorno sin imprimir valores. `browser.ts` crea el cliente de navegador de forma lazy con `createBrowserClient` y reutiliza una instancia solo en runtime de navegador. `server.ts` crea un cliente nuevo por request con `createServerClient`, recibe `Request`, `AstroCookies` y `Headers` explicitamente, y adapta cookies con `getAll`/`setAll`.

Estas fabricas no llaman `getSession`, `getUser`, `getClaims`, login, logout ni consultas durante import. El middleware llama `getUser()` solo durante la request, interpreta la falta de sesion como `anonymous`, propaga `Set-Cookie`, `Cache-Control` y `Pragma`, y deja `unconfigured` cuando falta entorno Supabase. No usa `getSession()` como autoridad ni expone tokens, sesion completa, claves o roles en `Astro.locals`.

El adaptador continua siendo `@astrojs/cloudflare` con `output: 'server'`; no se agrega otro runtime.

## Contexto de sesion SSR

`Astro.locals.auth` contiene `status`, `user` y `supabase`. Los estados posibles son `unconfigured`, `anonymous`, `authenticated` y `error`. El usuario local solo contiene `id` y `email`; cuando no hay usuario validado es `null`. El cliente `supabase` es el cliente server por request o `null` si la configuracion no esta disponible.

Este contexto no autoriza rutas por si solo. Las decisiones de autorizacion futuras deben ejecutarse en servidor y mantener PostgreSQL como autoridad de roles mediante RLS y funciones controladas.

## Ciclo de vida Auth/profiles

`auth.users` es la identidad administrada por Supabase. `public.profiles` contiene datos de aplicacion: `user_id`, email normalizado, nombre visible y estado de cuenta. PostgreSQL valida el dominio completo del email contra `public.allowed_email_domains` antes de insertar o cambiar `auth.users.email`; un valor invalido hace rollback de la operacion.

Despues de crear un usuario Auth valido, un trigger crea el perfil con `display_name = null` y `account_status = active`. Despues de cambiar el email, solo sincroniza `profiles.email` y `profiles.updated_at`; no toca nombre visible, estado, roles ni auditoria. Una migracion correctiva agrega `private.reconcile_auth_user_profiles()` para perfiles preexistentes: recrea perfiles faltantes, corrige emails obsoletos, preserva `display_name`, `account_status` y `created_at`, y aborta sin cambios parciales si un email ya pertenece al perfil de otro `user_id`. La eliminacion del perfil sigue el `ON DELETE CASCADE` existente.

No se copian automaticamente `raw_user_meta_data`, `app_metadata`, proveedor OAuth, avatar, tokens ni informacion de Google. No se asigna `student` ni ningun otro rol, y no existe administrador automatico. Google OAuth pertenece a 3B.2; un hook remoto Before User Created puede agregarse despues como validacion anticipada, pero no reemplaza los triggers PostgreSQL.

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
