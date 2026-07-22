# Politica De Seguridad

## Etapa Soportada

La etapa 3A.2A mantiene la aplicacion Astro sin login visible, middleware, OAuth ni clientes usados por paginas de autenticacion. Agrega configuracion de entorno y fabricas Supabase SSR sobre los fundamentos locales de PostgreSQL para roles, auditoria y RLS. No conecta Cloudflare R2 ni proveedores OAuth.

## Reporte

Reportar vulnerabilidades sospechadas por un canal privado de mantenedores o mediante GitHub private vulnerability reporting si esta habilitado en el repositorio. No publicar detalles de explotacion en issues publicos.

## Secretos

Nunca commitear secretos, tokens, passwords ni credenciales reales. Los archivos .env permanecen ignorados excepto .env.example, que solo debe contener comentarios o placeholders. Los valores reales de `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY` deben vivir en .env.local. La publishable key puede estar disponible al navegador porque no concede privilegios administrativos; la seguridad real depende de RLS, permisos de PostgreSQL y validaciones del servidor. La aplicacion no debe usar la llave `service_role`; cualquier mencion debe limitarse a documentar por que no se usa.

## Riesgos Registrados

- `docs/security/dependency-risk-register.md` contiene DR-001 para la cadena temporalmente aceptada `@astrojs/cloudflare -> @cloudflare/vite-plugin -> miniflare -> sharp@0.34.5`.

## Expectativas Futuras

- Validar autorizacion en el servidor.
- Mantener PostgreSQL como autoridad de roles.
- Agregar renovacion de sesion en middleware recien en 3A.2B.
- Aplicar minimo privilegio a roles de Supabase y bindings de Cloudflare.
- Mantener URLs privadas de archivos con vida corta y generadas del lado servidor.
- Revisar politicas de base de datos y acceso a storage antes de habilitar datos reales.
