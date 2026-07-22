# Autenticacion y autorizacion

La etapa 3A.1 agrega fundamentos locales de PostgreSQL para identidad, roles, permisos, auditoria y Row Level Security. No integra Supabase con paginas Astro, no crea middleware, no configura OAuth, no usa cookies y no mueve el catalogo academico fuera de `src/content/catalog/`.

## Separacion de responsabilidades

Autenticacion responde quien es el usuario. En una etapa posterior Supabase Auth emitira la identidad y `auth.uid()` permitira resolver el UUID del usuario actual dentro de PostgreSQL. En esta etapa solo se crean las tablas y politicas que referencian `auth.users`; la creacion automatica de perfiles se conectara en la etapa 3B.

Autorizacion responde que puede hacer ese usuario. PostgreSQL es la fuente autoritativa para roles: `public.user_roles` conserva asignaciones historicas, las funciones de autorizacion consultan asignaciones activas con `auth.uid()`, y las politicas RLS se evaluan en el servidor.

## Decisiones de seguridad

Los roles no se guardan en `localStorage` ni en estado enviado por el navegador. Cualquier dato controlado por el cliente puede manipularse, por lo que la autoridad vive en PostgreSQL y se consulta del lado servidor.

La aplicacion no usa la llave `service_role`. Esa llave omite RLS y queda reservada para tareas administrativas fuera del runtime de Astro. Las funciones `SECURITY DEFINER` creadas en esta etapa tienen `search_path` explicito, no usan SQL dinamico y solo conceden `EXECUTE` a `authenticated` cuando hace falta.

No se implementan custom JWT claims todavia. Duplicar roles en claims adelanta problemas de invalidacion y revocacion; para 3A.1 los roles activos se leen desde PostgreSQL en cada decision de autorizacion. Si una etapa futura necesita claims por rendimiento, debera registrar un ADR y definir invalidacion segura.

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
