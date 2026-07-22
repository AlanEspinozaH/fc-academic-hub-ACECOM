# ADR 0005: Fundamentos de RBAC en PostgreSQL

## Estado

Aceptada

## Contexto

La plataforma necesitara identidad institucional, roles comunitarios, auditoria y autorizacion validada en servidor antes de permitir materiales restringidos, revisiones o administracion. El catalogo academico permanece estatico en `src/content/catalog/` y no debe migrarse a PostgreSQL en esta etapa.

La etapa 3A.1 debe crear fundamentos reproducibles sin conectar Supabase a paginas Astro, sin login, sin OAuth, sin clientes Supabase en la aplicacion y sin recursos remotos.

## Decision

Crear configuracion local de Supabase, una migracion SQL versionada y pruebas pgTAP para:

- enums `app_role` y `account_status`;
- dominios de correo permitidos con `uni.pe`;
- perfiles vinculados a `auth.users`;
- historial de roles en `user_roles`;
- auditoria append-only en `role_audit_log`;
- funciones privadas de normalizacion y autorizacion basadas en `auth.uid()`;
- RPC publicas controladas para asignar y revocar roles;
- politicas RLS y permisos de columna para clientes `authenticated`.

Las funciones `SECURITY DEFINER` fijan `search_path` y no usan SQL dinamico. Los clientes no pueden indicar el UUID del actor; la autoridad se deriva de `auth.uid()`.

La matriz TypeScript de roles y permisos se agrega en `src/domain/auth/` con conjuntos explicitos. Sirve para dominio local futuro, pero PostgreSQL sigue siendo la fuente autoritativa de roles.

## Consecuencias

- Las reglas de autorizacion se pueden probar localmente con Docker, Supabase CLI y pgTAP.
- La asignacion de roles conserva historial y escribe auditoria atomica.
- `administrator` es el unico rol que puede gestionar roles por RPC.
- `moderator` puede tener permisos editoriales futuros, pero no administra roles.
- El primer administrador requiere bootstrap manual y auditable.
- La etapa 3B debera conectar creacion automatica de perfiles y flujos reales de autenticacion sin romper OAuth.

## Alternativas Consideradas

- Guardar roles en `localStorage`: rechazado porque el cliente puede manipularlo.
- Usar texto libre para roles: rechazado porque permite estados no modelados.
- Confiar en custom JWT claims desde esta etapa: rechazado por complejidad de revocacion e invalidacion.
- Usar la llave `service_role` en la aplicacion: rechazado porque omite RLS y amplia privilegios del runtime.
- Implementar bootstrap publico: rechazado porque crearia una superficie critica antes de tener autenticacion completa.
