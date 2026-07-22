# Bootstrap manual del primer administrador

Esta etapa no crea rutas publicas de bootstrap, administradores automaticos, contrasenas por defecto, conversion automatica del primer usuario ni emails administrativos hardcodeados. El primer administrador se asigna manualmente con privilegios administrativos de SQL y queda auditado.

Reemplazar los placeholders antes de ejecutar. No usar datos ficticios permanentes.

## Procedimiento

1. Confirmar que el usuario institucional existe en `auth.users` y que su correo pertenece a un dominio permitido.
2. Confirmar que existe su perfil en `public.profiles`. El perfil ya se crea automaticamente mediante el ciclo de vida de Auth de 3B.1.
3. Sustituir `<INSTITUTIONAL_EMAIL>` por el correo institucional confirmado.
4. Ejecutar el bloque `DO` con privilegios administrativos.
5. Verificar que existe exactamente una asignacion activa y una entrada de auditoria de bootstrap.

## SQL auditable

```sql
DO $bootstrap$
DECLARE
  target_user_id uuid;
  target_account_status public.account_status;
  target_email_allowed boolean;
  inserted_assignment_id bigint;
  active_assignment_count integer;
BEGIN
  SELECT
    auth_user.id,
    profile.account_status,
    private.is_allowed_email(profile.email)
  INTO
    target_user_id,
    target_account_status,
    target_email_allowed
  FROM auth.users AS auth_user
  JOIN public.profiles AS profile
    ON profile.user_id = auth_user.id
  WHERE private.normalize_email(auth_user.email)
      = private.normalize_email('<INSTITUTIONAL_EMAIL@uni.pe>')
    AND private.normalize_email(profile.email)
      = private.normalize_email(auth_user.email);

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION
      'Bootstrap aborted: matching auth user and profile not found';
  END IF;

  IF target_account_status <> 'active'::public.account_status THEN
    RAISE EXCEPTION
      'Bootstrap aborted: institutional profile is not active';
  END IF;

  IF target_email_allowed IS DISTINCT FROM true THEN
    RAISE EXCEPTION
      'Bootstrap aborted: institutional email domain is not enabled';
  END IF;

  INSERT INTO public.user_roles (
    user_id,
    role,
    granted_by,
    granted_at,
    reason
  )
  VALUES (
    target_user_id,
    'administrator'::public.app_role,
    target_user_id,
    now(),
    'first administrator manual bootstrap'
  )
  ON CONFLICT (user_id, role)
    WHERE revoked_at IS NULL
  DO NOTHING
  RETURNING id INTO inserted_assignment_id;

  IF inserted_assignment_id IS NOT NULL THEN
    INSERT INTO public.role_audit_log (
      actor_user_id,
      target_user_id,
      action,
      role,
      occurred_at,
      metadata
    )
    VALUES (
      target_user_id,
      target_user_id,
      'grant',
      'administrator'::public.app_role,
      now(),
      jsonb_build_object(
        'assignment_id', inserted_assignment_id,
        'bootstrap', true,
        'method', 'manual_sql_atomic_block'
      )
    );
  END IF;

  SELECT count(*)::integer
  INTO active_assignment_count
  FROM public.user_roles
  WHERE user_id = target_user_id
    AND role = 'administrator'::public.app_role
    AND revoked_at IS NULL;

  IF active_assignment_count <> 1 THEN
    RAISE EXCEPTION
      'Bootstrap aborted: expected exactly one active administrator assignment, found %',
      active_assignment_count;
  END IF;
END;
$bootstrap$;
```

Este bloque:

- aborta automaticamente si el perfil no existe;
- exige una cuenta `active`;
- valida que el dominio institucional este habilitado;
- crea exactamente una asignacion activa;
- escribe la auditoria dentro de la misma operacion;
- no requiere copiar el UUID manualmente.

El indice unico parcial `user_roles_one_active_role_per_user_idx` impide una segunda asignacion activa duplicada. El `ON CONFLICT ... WHERE revoked_at IS NULL DO NOTHING` evita crear auditoria si no se inserta una nueva asignacion.
