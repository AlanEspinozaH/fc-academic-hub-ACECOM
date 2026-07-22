BEGIN;

CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;

DO $$
BEGIN
	CREATE TYPE public.app_role AS ENUM (
		'student',
		'contributor',
		'reviewer',
		'moderator',
		'administrator'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
	CREATE TYPE public.account_status AS ENUM ('active', 'suspended', 'disabled');
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.normalize_email(email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
RETURNS NULL ON NULL INPUT
SET search_path = ''
AS $$
	SELECT lower(btrim(email));
$$;

CREATE OR REPLACE FUNCTION private.extract_email_domain(email text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
RETURNS NULL ON NULL INPUT
SET search_path = ''
AS $$
DECLARE
	normalized_email text := private.normalize_email(email);
	parts text[];
BEGIN
	parts := regexp_split_to_array(normalized_email, '@');

	IF array_length(parts, 1) <> 2 OR parts[1] = '' OR parts[2] = '' THEN
		RETURN NULL;
	END IF;

	IF parts[1] ~ '\s' OR parts[2] ~ '\s' THEN
		RETURN NULL;
	END IF;

	RETURN parts[2];
END;
$$;

CREATE TABLE IF NOT EXISTS public.allowed_email_domains (
	domain text PRIMARY KEY,
	enabled boolean NOT NULL DEFAULT true,
	created_at timestamptz NOT NULL DEFAULT now(),
	created_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
	CONSTRAINT allowed_email_domains_lowercase_check CHECK (domain = lower(domain)),
	CONSTRAINT allowed_email_domains_trimmed_check CHECK (domain = btrim(domain)),
	CONSTRAINT allowed_email_domains_no_whitespace_check CHECK (domain !~ '\s'),
	CONSTRAINT allowed_email_domains_no_at_check CHECK (position('@' in domain) = 0),
	CONSTRAINT allowed_email_domains_not_empty_check CHECK (domain <> '')
);

CREATE OR REPLACE FUNCTION private.normalize_allowed_email_domain()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	NEW.domain := lower(NEW.domain);

	IF TG_OP = 'INSERT' THEN
		NEW.created_at := COALESCE(NEW.created_at, now());

		IF auth.uid() IS NOT NULL THEN
			NEW.created_by := auth.uid();
		END IF;
	END IF;

	IF TG_OP = 'UPDATE' THEN
		NEW.created_at := OLD.created_at;
		NEW.created_by := OLD.created_by;
	END IF;

	IF NEW.domain IS NULL OR NEW.domain = '' THEN
		RAISE EXCEPTION 'email domain must not be empty' USING ERRCODE = '23514';
	END IF;

	IF NEW.domain <> btrim(NEW.domain) OR NEW.domain ~ '\s' THEN
		RAISE EXCEPTION 'email domain must not contain spaces' USING ERRCODE = '23514';
	END IF;

	IF position('@' in NEW.domain) > 0 THEN
		RAISE EXCEPTION 'email domain must not contain @' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalize_allowed_email_domain ON public.allowed_email_domains;
CREATE TRIGGER normalize_allowed_email_domain
BEFORE INSERT OR UPDATE ON public.allowed_email_domains
FOR EACH ROW
EXECUTE FUNCTION private.normalize_allowed_email_domain();

INSERT INTO public.allowed_email_domains (domain, enabled, created_at, created_by)
VALUES ('uni.pe', true, now(), NULL)
ON CONFLICT (domain) DO UPDATE
SET enabled = EXCLUDED.enabled;

CREATE OR REPLACE FUNCTION private.is_allowed_email(email text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	email_domain text := private.extract_email_domain(email);
BEGIN
	IF email_domain IS NULL THEN
		RETURN false;
	END IF;

	RETURN EXISTS (
		SELECT 1
		FROM public.allowed_email_domains AS allowed_domain
		WHERE allowed_domain.domain = email_domain
			AND allowed_domain.enabled
	);
END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
	user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
	email text NOT NULL UNIQUE,
	display_name text NULL,
	account_status public.account_status NOT NULL DEFAULT 'active',
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT profiles_email_normalized_check CHECK (email = private.normalize_email(email)),
	CONSTRAINT profiles_email_shape_check CHECK (private.extract_email_domain(email) IS NOT NULL),
	CONSTRAINT profiles_email_no_whitespace_check CHECK (email !~ '\s')
);

CREATE INDEX IF NOT EXISTS profiles_account_status_idx ON public.profiles (account_status);

CREATE OR REPLACE FUNCTION private.set_profile_defaults_and_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	IF TG_OP = 'INSERT' THEN
		NEW.created_at := COALESCE(NEW.created_at, now());
		NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
	END IF;

	IF TG_OP = 'UPDATE' THEN
		NEW.created_at := OLD.created_at;
		NEW.updated_at := now();
	END IF;

	IF TG_OP = 'INSERT' OR NEW.email IS DISTINCT FROM OLD.email THEN
		NEW.email := private.normalize_email(NEW.email);

		IF NOT private.is_allowed_email(NEW.email) THEN
			RAISE EXCEPTION 'profile email domain is not allowed' USING ERRCODE = '23514';
		END IF;
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_profile_defaults_and_validate ON public.profiles;
CREATE TRIGGER set_profile_defaults_and_validate
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION private.set_profile_defaults_and_validate();

CREATE TABLE IF NOT EXISTS public.user_roles (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	role public.app_role NOT NULL,
	granted_by uuid NOT NULL REFERENCES public.profiles(user_id),
	granted_at timestamptz NOT NULL DEFAULT now(),
	revoked_by uuid NULL REFERENCES public.profiles(user_id),
	revoked_at timestamptz NULL,
	reason text NULL,
	CONSTRAINT user_roles_revocation_pair_check CHECK (
		(revoked_by IS NULL AND revoked_at IS NULL)
		OR (revoked_by IS NOT NULL AND revoked_at IS NOT NULL)
	),
	CONSTRAINT user_roles_revoked_after_granted_check CHECK (
		revoked_at IS NULL OR revoked_at >= granted_at
	)
);

CREATE UNIQUE INDEX IF NOT EXISTS user_roles_one_active_role_per_user_idx
ON public.user_roles (user_id, role)
WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_roles_user_id_revoked_at_idx
ON public.user_roles (user_id, revoked_at);

CREATE INDEX IF NOT EXISTS user_roles_granted_by_idx
ON public.user_roles (granted_by);

CREATE INDEX IF NOT EXISTS user_roles_revoked_by_idx
ON public.user_roles (revoked_by)
WHERE revoked_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS user_roles_revoked_at_idx
ON public.user_roles (revoked_at);

CREATE TABLE IF NOT EXISTS public.role_audit_log (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	actor_user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	target_user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	action text NOT NULL,
	role public.app_role NOT NULL,
	occurred_at timestamptz NOT NULL DEFAULT now(),
	metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
	CONSTRAINT role_audit_log_action_check CHECK (action IN ('grant', 'revoke')),
	CONSTRAINT role_audit_log_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS role_audit_log_actor_occurred_at_idx
ON public.role_audit_log (actor_user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS role_audit_log_target_occurred_at_idx
ON public.role_audit_log (target_user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS role_audit_log_role_action_idx
ON public.role_audit_log (role, action);

CREATE OR REPLACE FUNCTION private.prevent_role_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	RAISE EXCEPTION 'role_audit_log is append-only' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS prevent_role_audit_log_update ON public.role_audit_log;
CREATE TRIGGER prevent_role_audit_log_update
BEFORE UPDATE OR DELETE ON public.role_audit_log
FOR EACH ROW
EXECUTE FUNCTION private.prevent_role_audit_log_mutation();

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
			AND profile.account_status = 'active'::public.account_status
	);
$$;

CREATE OR REPLACE FUNCTION private.can_manage_roles()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT private.has_role('administrator'::public.app_role);
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

	IF NOT EXISTS (
		SELECT 1 FROM public.profiles AS profile WHERE profile.user_id = target_user_id
	) THEN
		RAISE EXCEPTION 'target profile does not exist' USING ERRCODE = '23503';
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

CREATE OR REPLACE FUNCTION public.revoke_user_role(
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
	revoked_assignment_id bigint;
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
		RAISE EXCEPTION 'users cannot revoke roles from themselves' USING ERRCODE = '42501';
	END IF;

	IF normalized_reason IS NOT NULL THEN
		audit_metadata := audit_metadata || jsonb_build_object('reason', normalized_reason);
	END IF;

	UPDATE public.user_roles AS assigned_role
	SET revoked_by = actor_user_id,
		revoked_at = now()
	WHERE assigned_role.user_id = target_user_id
		AND assigned_role.role = requested_role
		AND assigned_role.revoked_at IS NULL
	RETURNING assigned_role.id INTO revoked_assignment_id;

	IF revoked_assignment_id IS NULL THEN
		RAISE EXCEPTION 'active role assignment does not exist' USING ERRCODE = 'P0002';
	END IF;

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
		'revoke',
		requested_role,
		now(),
		audit_metadata || jsonb_build_object('assignment_id', revoked_assignment_id)
	);

	RETURN revoked_assignment_id;
END;
$$;

ALTER TABLE public.allowed_email_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS allowed_email_domains_select_admin ON public.allowed_email_domains;
CREATE POLICY allowed_email_domains_select_admin
ON public.allowed_email_domains
FOR SELECT
TO authenticated
USING ((SELECT private.can_manage_roles()));

DROP POLICY IF EXISTS allowed_email_domains_insert_admin ON public.allowed_email_domains;
CREATE POLICY allowed_email_domains_insert_admin
ON public.allowed_email_domains
FOR INSERT
TO authenticated
WITH CHECK ((SELECT private.can_manage_roles()));

DROP POLICY IF EXISTS allowed_email_domains_update_admin ON public.allowed_email_domains;
CREATE POLICY allowed_email_domains_update_admin
ON public.allowed_email_domains
FOR UPDATE
TO authenticated
USING ((SELECT private.can_manage_roles()))
WITH CHECK ((SELECT private.can_manage_roles()));

DROP POLICY IF EXISTS allowed_email_domains_delete_admin ON public.allowed_email_domains;
CREATE POLICY allowed_email_domains_delete_admin
ON public.allowed_email_domains
FOR DELETE
TO authenticated
USING ((SELECT private.can_manage_roles()));

DROP POLICY IF EXISTS profiles_select_own_or_admin ON public.profiles;
CREATE POLICY profiles_select_own_or_admin
ON public.profiles
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()) OR (SELECT private.can_manage_roles()));

DROP POLICY IF EXISTS profiles_update_own_display_name ON public.profiles;
CREATE POLICY profiles_update_own_display_name
ON public.profiles
FOR UPDATE
TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_roles_select_own_active_or_admin ON public.user_roles;
CREATE POLICY user_roles_select_own_active_or_admin
ON public.user_roles
FOR SELECT
TO authenticated
USING (
	(user_id = (SELECT auth.uid()) AND revoked_at IS NULL)
	OR (SELECT private.can_manage_roles())
);

DROP POLICY IF EXISTS role_audit_log_select_admin ON public.role_audit_log;
CREATE POLICY role_audit_log_select_admin
ON public.role_audit_log
FOR SELECT
TO authenticated
USING ((SELECT private.can_manage_roles()));

REVOKE ALL ON TABLE public.allowed_email_domains FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.user_roles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.role_audit_log FROM PUBLIC, anon, authenticated;

REVOKE ALL ON SEQUENCE public.user_roles_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.role_audit_log_id_seq FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TYPE public.app_role FROM PUBLIC;
REVOKE ALL ON TYPE public.account_status FROM PUBLIC;
GRANT USAGE ON TYPE public.app_role TO authenticated;
GRANT USAGE ON TYPE public.account_status TO authenticated;

GRANT USAGE ON SCHEMA private TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.allowed_email_domains TO authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (display_name) ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.user_roles TO authenticated;
GRANT SELECT ON TABLE public.role_audit_log TO authenticated;

REVOKE ALL ON FUNCTION private.normalize_email(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.extract_email_domain(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.is_allowed_email(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.has_role(public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.has_any_role(public.app_role[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_manage_roles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.grant_user_role(uuid, public.app_role, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_user_role(uuid, public.app_role, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION private.normalize_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.extract_email_domain(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_allowed_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_role(public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_any_role(public.app_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_roles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_user_role(uuid, public.app_role, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_user_role(uuid, public.app_role, text) TO authenticated;

COMMIT;
