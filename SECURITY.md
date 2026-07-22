# Politica De Seguridad

## Etapa Soportada

La etapa 3A.1 mantiene la aplicacion Astro sin login ni clientes Supabase, y agrega fundamentos locales de PostgreSQL para roles, auditoria y RLS. No conecta Cloudflare R2 ni proveedores OAuth.

## Reporte

Reportar vulnerabilidades sospechadas por un canal privado de mantenedores o mediante GitHub private vulnerability reporting si esta habilitado en el repositorio. No publicar detalles de explotacion en issues publicos.

## Secretos

Nunca commitear secretos, tokens, passwords ni credenciales reales. Los archivos .env permanecen ignorados excepto .env.example, que solo debe contener comentarios o placeholders. La aplicacion no debe usar la llave `service_role`; cualquier mencion debe limitarse a documentar por que no se usa.

## Riesgos Registrados

- `docs/security/dependency-risk-register.md` contiene DR-001 para la cadena temporalmente aceptada `@astrojs/cloudflare -> @cloudflare/vite-plugin -> miniflare -> sharp@0.34.5`.

## Expectativas Futuras

- Validar autorizacion en el servidor.
- Aplicar minimo privilegio a roles de Supabase y bindings de Cloudflare.
- Mantener URLs privadas de archivos con vida corta y generadas del lado servidor.
- Revisar politicas de base de datos y acceso a storage antes de habilitar datos reales.
