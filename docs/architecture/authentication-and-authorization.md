# Autenticacion y autorizacion

La etapa 3A.2A agrega configuracion de entorno y fabricas de clientes Supabase para Astro SSR sobre los fundamentos locales de PostgreSQL de 3A.1. No implementa login visible, middleware, OAuth, endpoints de callback, rutas logout ni uso de clientes desde paginas de autenticacion. Tampoco mueve el catalogo academico fuera de `src/content/catalog/`.

## Separacion de responsabilidades

Autenticacion responde quien es el usuario. En una etapa posterior Supabase Auth emitira la identidad y `auth.uid()` permitira resolver el UUID del usuario actual dentro de PostgreSQL. En 3A.2A solo existe la base de clientes SSR; no hay pantallas de ingreso, OAuth ni renovacion de sesion. La creacion automatica de perfiles se conectara en la etapa 3B.

Autorizacion responde que puede hacer ese usuario. PostgreSQL es la fuente autoritativa para roles: `public.user_roles` conserva asignaciones historicas, las funciones de autorizacion consultan asignaciones activas con `auth.uid()`, y las politicas RLS se evaluan en el servidor.

## Decisiones de seguridad

La configuracion publica de Supabase se limita a `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY`. La publishable key puede estar disponible en el navegador porque identifica el proyecto y opera bajo las reglas de Auth, permisos y RLS; no reemplaza autorizacion del servidor ni concede privilegios administrativos. Las llaves secretas quedan fuera de Astro y no se declaran en `.env.example`.

Los roles no se guardan en `localStorage` ni en estado enviado por el navegador. Cualquier dato controlado por el cliente puede manipularse, por lo que la autoridad vive en PostgreSQL y se consulta del lado servidor.

La aplicacion no usa la llave `service_role`. Esa llave omite RLS y queda reservada para tareas administrativas fuera del runtime de Astro. Las funciones `SECURITY DEFINER` creadas en esta etapa tienen `search_path` explicito, no usan SQL dinamico y solo conceden `EXECUTE` a `authenticated` cuando hace falta.

No se implementan custom JWT claims todavia. Duplicar roles en claims adelanta problemas de invalidacion y revocacion; los roles activos deben seguir resolviendose desde PostgreSQL en cada decision de autorizacion. Si una etapa futura necesita claims por rendimiento, debera registrar un ADR y definir invalidacion segura.

## Clientes SSR

`src/infrastructure/supabase/config.ts` valida entorno sin imprimir valores. `browser.ts` crea el cliente de navegador de forma lazy con `createBrowserClient` y reutiliza una instancia solo en runtime de navegador. `server.ts` crea un cliente nuevo por request con `createServerClient`, recibe `Request` y `AstroCookies` explicitamente, y adapta cookies con `getAll`/`setAll`.

Estas fabricas no llaman `getSession`, `getUser`, `getClaims`, login, logout ni consultas durante import. La renovacion de sesion en middleware pertenece a 3A.2B.

El adaptador continua siendo `@astrojs/cloudflare` con `output: 'server'`; no se agrega otro runtime.

## Entorno local

Supabase local se configura en `supabase/config.toml`. La CLI probada para esta etapa fue `supabase 2.109.1` via `npx --yes supabase@latest`. El entorno local no debe exponerse a Internet.

Comandos locales:

```sh
npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
npx --yes supabase@latest db lint --local
npx --yes supabase@latest stop
```

No usar `supabase login`, `supabase link`, `db push` ni variantes `--linked` para esta etapa.
