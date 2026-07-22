# Modelo de roles y permisos

La etapa 3A.1 define roles en PostgreSQL mediante el enum `public.app_role` y replica la matriz de permisos en TypeScript para reglas de dominio locales. La matriz TypeScript no reemplaza RLS; es una representacion para codigo de aplicacion futuro.

## Roles

- `student`
- `contributor`
- `reviewer`
- `moderator`
- `administrator`

Los estados de cuenta viven en `public.account_status`: `active`, `suspended` y `disabled`. Las funciones de autorizacion solo consideran perfiles `active`.

## Permisos

- `catalog.read`
- `restricted_material.read`
- `submission.create`
- `submission.review`
- `submission.publish`
- `role.manage`
- `account.suspend`
- `audit.read`

Matriz:

| Rol             | Permisos                                       |
| --------------- | ---------------------------------------------- |
| `student`       | `catalog.read`, `restricted_material.read`     |
| `contributor`   | permisos de `student`, `submission.create`     |
| `reviewer`      | permisos de `contributor`, `submission.review` |
| `moderator`     | permisos de `reviewer`, `submission.publish`   |
| `administrator` | todos los permisos                             |

La implementacion TypeScript usa conjuntos explicitos por rol y valida entradas externas en runtime. No usa comparaciones numericas de jerarquia.

## Gestion de roles

Los clientes no tienen `INSERT`, `UPDATE` ni `DELETE` directo sobre `public.user_roles`. La asignacion y revocacion se hacen mediante:

- `public.grant_user_role(target_user_id uuid, role app_role, reason text)`
- `public.revoke_user_role(target_user_id uuid, role app_role, reason text)`

Ambas funciones usan `auth.uid()` para identificar al actor. Un cliente no puede proporcionar el UUID del actor. Solo usuarios con rol activo `administrator` pueden ejecutarlas con exito. `moderator`, `reviewer`, `contributor` y `student` no pueden gestionar roles. Ningun usuario puede autoasignarse ni autorrevocarse roles por RPC.

`public.user_roles` conserva historial mediante `revoked_at` y `revoked_by`. Un indice unico parcial impide dos asignaciones activas del mismo rol para el mismo usuario. La creacion automatica de `public.profiles` desde `auth.users` no asigna roles ni crea administradores; cualquier asignacion futura debe tener un actor real en `granted_by` y su auditoria correspondiente.

## Auditoria

`public.role_audit_log` registra acciones `grant` y `revoke`. Los clientes no pueden insertar, actualizar ni borrar auditoria; las entradas de RPC se escriben dentro de la misma transaccion que el cambio de rol. La tabla tiene trigger de bloqueo para `UPDATE` y `DELETE`, por lo que es append-only.
