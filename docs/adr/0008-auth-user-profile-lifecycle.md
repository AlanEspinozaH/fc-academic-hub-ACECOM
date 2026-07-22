# ADR 0008: Ciclo de vida Auth/profiles

## Estado

Aceptada

## Contexto

La etapa 3B.1 debe conectar la identidad administrada por Supabase Auth con los datos minimos de aplicacion en `public.profiles`. La etapa 3A.1 ya creo dominios de correo permitidos, perfiles, roles, auditoria, RLS y funciones privadas de normalizacion. La etapa 3A.2B ya expone identidad validada en `Astro.locals`, pero no crea login visible, OAuth, callback, logout, rutas privadas ni consultas de roles desde Astro.

Supabase ofrece un hook remoto Before User Created, pero la configuracion local actual no lo expone como una pieza reproducible clara para esta etapa. La regla autoritativa debe vivir en PostgreSQL y ejecutarse de forma local mediante migraciones y pgTAP.

## Decision

Crear una migracion PostgreSQL nueva con dos funciones privadas de trigger:

- `private.enforce_allowed_auth_user_email()` valida `auth.users.email` antes de `INSERT` y `UPDATE OF email`.
- `private.sync_auth_user_profile()` sincroniza `public.profiles` despues de `INSERT` y `UPDATE OF email`.

La validacion usa las funciones existentes `private.normalize_email`, `private.extract_email_domain` y `private.is_allowed_email`. El dominio se compara como valor completo contra `public.allowed_email_domains.domain` habilitado, no mediante sufijos, `LIKE` ni subdominios implicitos. Emails nulos, vacios, sin arroba o con dominio no habilitado abortan la transaccion con un error controlado de correo institucional requerido.

Al insertar un usuario Auth valido, PostgreSQL crea un perfil con `user_id`, email normalizado, `display_name = null` y `account_status = active`. La operacion es idempotente y no sobrescribe campos administrados de forma destructiva. Al cambiar el email de `auth.users`, solo se actualizan `profiles.email` y `profiles.updated_at`; se conservan `display_name` y `account_status`.

La eliminacion de perfiles sigue dependiendo del `ON DELETE CASCADE` existente desde `public.profiles.user_id` hacia `auth.users(id)`.

La migracion revisa usuarios Auth preexistentes antes del backfill. Si existe cualquier email no permitido, aborta sin crear perfiles parciales. Para usuarios validos existentes, inserta perfiles faltantes con `ON CONFLICT DO NOTHING` y no sobrescribe `display_name`, `account_status` ni `created_at` de perfiles existentes.

Las funciones de trigger usan `SECURITY DEFINER`, fijan `search_path` vacio, referencian objetos con nombres totalmente calificados y no usan SQL dinamico. `EXECUTE` se revoca de `PUBLIC`, `anon` y `authenticated`; los triggers sobre `auth.users` son la unica ruta esperada de ejecucion.

## Seguridad

`auth.users` es la identidad administrada por Supabase. `public.profiles` contiene datos de aplicacion y no copia automaticamente `raw_user_meta_data`, `app_metadata`, proveedor OAuth, avatar, tokens ni informacion de Google. Esos datos no son autoridad de autorizacion.

La creacion de perfiles no asigna `student` ni ningun otro rol. `public.user_roles` conserva `granted_by` y auditoria, por lo que la asignacion requiere un actor real y auditable. Tampoco se crea un administrador automaticamente; el primer administrador sigue siendo un bootstrap manual y auditable.

Google OAuth pertenece a 3B.2. Un Before User Created hook remoto puede agregarse despues como validacion anticipada de experiencia de usuario, pero no reemplaza los triggers PostgreSQL ni forma parte de esta implementacion.

## Consecuencias

- El alta de Auth y el perfil de aplicacion quedan sincronizados de forma reproducible localmente.
- Un email no institucional hace rollback de la creacion o cambio de usuario.
- Los dominios habilitados siguen siendo datos administrativos en `public.allowed_email_domains`.
- Las rutas Astro, login, OAuth, logout y lectura de roles permanecen fuera de alcance.
- Las futuras etapas deben mantener PostgreSQL como autoridad de roles y no confiar en metadata enviada por proveedores OAuth.

## Alternativas Consideradas

- Configurar Before User Created en `supabase/config.toml`: rechazado porque no es necesario ni claramente reproducible en la configuracion local actual.
- Usar Edge Functions: rechazado porque agregaria runtime y despliegue fuera de las migraciones PostgreSQL locales.
- Asignar automaticamente `student`: rechazado porque `user_roles` exige actor y auditoria.
- Crear un administrador automatico: rechazado porque rompe el bootstrap manual y auditable de 3A.1.
- Validar dominio con sufijos: rechazado porque aceptaria dominios como `falsauni.pe` o subdominios no habilitados.
