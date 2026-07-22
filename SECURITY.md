# Politica De Seguridad

## Etapa Soportada

La etapa 3B.2A mantiene el catalogo publico y agrega el flujo de aplicacion para Google OAuth con PKCE: pagina de acceso, inicio por POST, callback de aplicacion y logout por POST. No configura todavia credenciales reales de Google, proyecto Supabase remoto, paginas privadas, proteccion del catalogo, administracion de roles ni Cloudflare R2.

## Reporte

Reportar vulnerabilidades sospechadas por un canal privado de mantenedores o mediante GitHub private vulnerability reporting si esta habilitado en el repositorio. No publicar detalles de explotacion en issues publicos.

## Secretos

Nunca commitear secretos, tokens, passwords ni credenciales reales. Los archivos .env permanecen ignorados excepto .env.example, que solo debe contener comentarios o placeholders. Los valores reales de `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY` deben vivir en .env.local. Las credenciales reales de Google pertenecen a una etapa posterior y no deben agregarse al repositorio.

La publishable key puede estar disponible al navegador porque no concede privilegios administrativos; la seguridad real depende de RLS, permisos de PostgreSQL y validaciones del servidor. `Astro.locals.auth` no debe contener tokens, sesiones completas, claves ni roles. La aplicacion no debe usar la llave `service_role`; cualquier mencion debe limitarse a documentar por que no se usa. `public.profiles` no copia automaticamente metadata OAuth, proveedor, avatar ni tokens desde Auth.

## OAuth Institucional

Google OAuth solo confirma identidad ante Supabase Auth. No es autoridad del dominio institucional, roles ni permisos. La aplicacion no debe confiar en `hd`, emails mostrados por el navegador, metadata de Auth ni metadata del proveedor. Los triggers PostgreSQL existentes siguen validando el dominio exacto del email en `auth.users`.

El callback de aplicacion `/auth/callback` intercambia el codigo PKCE con `exchangeCodeForSession` y valida identidad con `getUser`. Los errores de Google, Supabase o PostgreSQL se presentan como mensajes genericos controlados, sin reflejar detalles internos.

La aplicacion no necesita APIs de Google y no conserva `provider_token` ni `provider_refresh_token`. Las fabricas Supabase eliminan esos campos de las respuestas exitosas del endpoint `/auth/v1/token` antes de que `auth-js` procese y persista la sesion. No se confia en la serializacion de cookies para garantizar esta propiedad.

Los endpoints que modifican estado aceptan POST. El inicio OAuth y el logout validan `Origin` cuando esta presente. Los destinos `next` deben ser internos y no pueden reingresar a `/auth`.

## Riesgos Registrados

- `docs/security/dependency-risk-register.md` contiene DR-001 para la cadena temporalmente aceptada `@astrojs/cloudflare -> @cloudflare/vite-plugin -> miniflare -> sharp@0.34.5`.
- Una actualizacion futura de Supabase SSR/Auth debe reauditar la forma de la respuesta del endpoint de token y la persistencia de sesion.

## Expectativas Futuras

- Validar autorizacion en el servidor.
- Mantener la validacion de dominio institucional en PostgreSQL como regla autoritativa; un hook Before User Created remoto solo puede ser una mejora anticipada futura.
- Mantener PostgreSQL como autoridad de roles.
- Mantener el middleware SSR limitado a identidad validada hasta que existan rutas privadas.
- Aplicar minimo privilegio a roles de Supabase y bindings de Cloudflare.
- Mantener URLs privadas de archivos con vida corta y generadas del lado servidor.
- Revisar politicas de base de datos y acceso a storage antes de habilitar datos reales.
