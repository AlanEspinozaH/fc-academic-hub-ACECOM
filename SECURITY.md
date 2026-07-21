# Politica De Seguridad

## Etapa Soportada

La etapa 1 es una base Astro renderizada en servidor con un endpoint de health y datos ficticios de demostracion. No conecta Supabase, Cloudflare R2 ni proveedores de autenticacion.

## Reporte

Reportar vulnerabilidades sospechadas por un canal privado de mantenedores o mediante GitHub private vulnerability reporting si esta habilitado en el repositorio. No publicar detalles de explotacion en issues publicos.

## Secretos

Nunca commitear secretos, tokens, passwords ni credenciales reales. Los archivos .env permanecen ignorados excepto .env.example, que solo debe contener comentarios o placeholders.

## Expectativas Futuras

- Validar autorizacion en el servidor.
- Aplicar minimo privilegio a roles de Supabase y bindings de Cloudflare.
- Mantener URLs privadas de archivos con vida corta y generadas del lado servidor.
- Revisar politicas de base de datos y acceso a storage antes de habilitar datos reales.
