BEGIN;

CREATE OR REPLACE FUNCTION private.has_role(requested_role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT EXISTS (
		SELECT 1
		FROM public.user_roles AS assigned_role
		INNER JOIN public.profiles AS profile
			ON profile.user_id = assigned_role.user_id
		WHERE assigned_role.user_id = auth.uid()
			AND assigned_role.role = requested_role
			AND assigned_role.revoked_at IS NULL
			AND profile.identity_kind = 'institutional'::public.identity_kind
			AND profile.account_status = 'active'::public.account_status
	);
$$;

CREATE OR REPLACE FUNCTION private.has_any_role(requested_roles public.app_role[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT EXISTS (
		SELECT 1
		FROM public.user_roles AS assigned_role
		INNER JOIN public.profiles AS profile
			ON profile.user_id = assigned_role.user_id
		WHERE assigned_role.user_id = auth.uid()
			AND assigned_role.role = ANY(requested_roles)
			AND assigned_role.revoked_at IS NULL
			AND profile.identity_kind = 'institutional'::public.identity_kind
			AND profile.account_status = 'active'::public.account_status
	);
$$;

CREATE OR REPLACE FUNCTION public.grant_user_role(
	target_user_id uuid,
	"role" public.app_role,
	reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_role public.app_role := "role";
	target_identity_kind public.identity_kind;
	target_account_status public.account_status;
	new_assignment_id bigint;
	normalized_reason text := NULLIF(btrim(reason), '');
	audit_metadata jsonb := '{}'::jsonb;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_manage_roles() THEN
		RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501';
	END IF;

	IF target_user_id IS NULL OR requested_role IS NULL THEN
		RAISE EXCEPTION 'target user and role are required' USING ERRCODE = '22004';
	END IF;

	IF actor_user_id = target_user_id THEN
		RAISE EXCEPTION 'users cannot grant roles to themselves' USING ERRCODE = '42501';
	END IF;

	SELECT profile.identity_kind, profile.account_status
	INTO target_identity_kind, target_account_status
	FROM public.profiles AS profile
	WHERE profile.user_id = target_user_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'target profile does not exist' USING ERRCODE = '23503';
	END IF;

	IF target_identity_kind <> 'institutional'::public.identity_kind
		OR target_account_status <> 'active'::public.account_status THEN
		RAISE EXCEPTION 'target profile is not eligible for internal roles' USING ERRCODE = '42501';
	END IF;

	IF normalized_reason IS NOT NULL THEN
		audit_metadata := audit_metadata || jsonb_build_object('reason', normalized_reason);
	END IF;

	INSERT INTO public.user_roles (user_id, role, granted_by, granted_at, reason)
	VALUES (target_user_id, requested_role, actor_user_id, now(), normalized_reason)
	RETURNING id INTO new_assignment_id;

	INSERT INTO public.role_audit_log (
		actor_user_id,
		target_user_id,
		action,
		role,
		occurred_at,
		metadata
	)
	VALUES (
		actor_user_id,
		target_user_id,
		'grant',
		requested_role,
		now(),
		audit_metadata || jsonb_build_object('assignment_id', new_assignment_id)
	);

	RETURN new_assignment_id;
END;
$$;

COMMIT;
