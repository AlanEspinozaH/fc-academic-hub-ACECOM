# Bootstrap manual del primer administrador

Esta etapa no crea rutas publicas de bootstrap, administradores automaticos, contrasenas por defecto, conversion automatica del primer usuario ni emails administrativos hardcodeados. El primer administrador se asigna manualmente con privilegios administrativos de SQL y queda auditado.

Reemplazar los placeholders antes de ejecutar. No usar datos ficticios permanentes.

## Procedimiento

1. Confirmar que el usuario institucional existe en `auth.users` y que su correo pertenece a un dominio permitido.
2. Confirmar que existe su perfil en `public.profiles`. La creacion automatica del perfil se conectara en la etapa 3B; en 3A.1 no hay trigger sobre `auth.users`.
3. Iniciar una transaccion SQL con privilegios administrativos.
4. Insertar la asignacion activa `administrator`.
5. Insertar la entrada de auditoria correspondiente.
6. Confirmar la transaccion.
7. Verificar que existe exactamente una asignacion activa.

## SQL auditable

```sql
BEGIN;

-- 1. Sustituir por el UUID real confirmado en auth.users.
WITH bootstrap_target AS (
  SELECT '<USER_UUID>'::uuid AS user_id
), confirmed_profile AS (
  SELECT profiles.user_id
  FROM public.profiles
  INNER JOIN bootstrap_target
    ON bootstrap_target.user_id = profiles.user_id
  WHERE private.is_allowed_email(profiles.email)
), inserted_role AS (
  INSERT INTO public.user_roles (user_id, role, granted_by, granted_at, reason)
  SELECT
    confirmed_profile.user_id,
    'administrator'::public.app_role,
    confirmed_profile.user_id,
    now(),
    'first administrator manual bootstrap'
  FROM confirmed_profile
  ON CONFLICT (user_id, role) WHERE revoked_at IS NULL DO NOTHING
  RETURNING id, user_id, role
)
INSERT INTO public.role_audit_log (
  actor_user_id,
  target_user_id,
  action,
  role,
  occurred_at,
  metadata
)
SELECT
  inserted_role.user_id,
  inserted_role.user_id,
  'grant',
  inserted_role.role,
  now(),
  jsonb_build_object(
    'assignment_id', inserted_role.id,
    'bootstrap', true,
    'method', 'manual_sql_transaction'
  )
FROM inserted_role;

-- Debe devolver 1. Si devuelve 0, no confirmar sin investigar.
SELECT count(*) AS active_administrator_assignments
FROM public.user_roles
WHERE user_id = '<USER_UUID>'::uuid
  AND role = 'administrator'
  AND revoked_at IS NULL;

COMMIT;
```

El indice unico parcial `user_roles_one_active_role_per_user_idx` impide una segunda asignacion activa duplicada. El `ON CONFLICT ... WHERE revoked_at IS NULL DO NOTHING` evita crear auditoria si no se inserta una nueva asignacion.
