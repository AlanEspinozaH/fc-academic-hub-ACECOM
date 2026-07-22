# Configuración remota de Google OAuth y Supabase

## Alcance

La etapa 3B.2B conecta FC Academic Hub con un proyecto Supabase remoto y un
cliente Google OAuth de tipo Web application. La aplicación fue validada en
desarrollo local y todavía no está desplegada públicamente.

Este documento no contiene Client Secret, tokens, cookies, contraseñas,
publishable keys reales ni el contenido de `.env.local`.

## Responsabilidades

- Google confirma la identidad.
- Supabase Auth administra OAuth y la sesión.
- PostgreSQL valida el dominio institucional.
- `public.profiles` mantiene el perfil de aplicación.
- `public.user_roles` es la autoridad de roles y permisos.

El primer inicio de sesión no asigna roles automáticamente.

## Configuración local

Los valores reales se guardan exclusivamente en `.env.local`:

```dotenv
PUBLIC_SUPABASE_URL="https://<PROJECT_REF>.supabase.co"
PUBLIC_SUPABASE_PUBLISHABLE_KEY="<PUBLISHABLE_KEY>"
```

`.env.local` permanece ignorado por Git. Astro no utiliza `service_role` ni
claves secretas de Supabase.

## Supabase Auth

Configuración validada:

- Site URL: `http://localhost:4321`
- Redirect URL: `http://localhost:4321/auth/callback`
- Redirect URL alternativa: `http://127.0.0.1:4321/auth/callback`
- proveedor Google habilitado;
- OAuth Server desactivado.

El Client ID y Client Secret se almacenan solamente en la configuración privada
del proveedor Google dentro de Supabase.

## Google Auth Platform

- audiencia External;
- estado Testing;
- cliente Web application;
- scopes `openid`, `userinfo.email` y `userinfo.profile`;
- callback `https://<PROJECT_REF>.supabase.co/auth/v1/callback`.

No se solicitan permisos de Gmail, Drive, Calendar ni otras APIs.

## Migraciones remotas

Antes de aplicar migraciones:

```sh
npx --yes supabase@2.109.1 projects list
npx --yes supabase@2.109.1 migration list
npx --yes supabase@2.109.1 db push --dry-run
```

Solo después de verificar el proyecto vinculado y el dry run:

```sh
npx --yes supabase@2.109.1 db push
npx --yes supabase@2.109.1 migration list
```

## Validaciones completadas

- login institucional mediante Google;
- callback Google → Supabase → Astro;
- persistencia de sesión SSR;
- creación de perfil activo;
- ausencia de roles automáticos;
- logout local mediante POST;
- permanencia del usuario remoto después del logout;
- rechazo de cuentas externas sin crear usuario ni perfil;
- redacción de tokens del proveedor cubierta por pruebas automatizadas;
- limpieza de fragmentos OAuth con detalles internos;
- mensajes visibles genéricos.

## Límites vigentes

- Google Auth Platform permanece en Testing.
- El catálogo continúa siendo público.
- No existen rutas privadas de recursos.
- No existe subida de archivos.
- No existe bucket Cloudflare R2.
- No existe despliegue público.
