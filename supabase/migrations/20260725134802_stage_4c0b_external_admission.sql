BEGIN;

CREATE TABLE public.external_identity_preauthorizations (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	normalized_email text NOT NULL,
	authorized_by uuid NOT NULL REFERENCES public.profiles(user_id),
	authorized_at timestamptz NOT NULL DEFAULT now(),
	reason text NULL,
	revoked_by uuid NULL REFERENCES public.profiles(user_id),
	revoked_at timestamptz NULL,
	revocation_reason text NULL,
	CONSTRAINT external_identity_preauthorizations_email_normalized_check
		CHECK (normalized_email = private.normalize_email(normalized_email)),
	CONSTRAINT external_identity_preauthorizations_email_shape_check
		CHECK (private.extract_email_domain(normalized_email) IS NOT NULL),
	CONSTRAINT external_identity_preauthorizations_email_no_whitespace_check
		CHECK (normalized_email !~ '\s'),
	CONSTRAINT external_identity_preauthorizations_revocation_pair_check
		CHECK ((revoked_by IS NULL AND revoked_at IS NULL) OR (revoked_by IS NOT NULL AND revoked_at IS NOT NULL)),
	CONSTRAINT external_identity_preauthorizations_revocation_time_check
		CHECK (revoked_at IS NULL OR revoked_at >= authorized_at)
);

CREATE UNIQUE INDEX external_identity_preauthorizations_active_email_idx
ON public.external_identity_preauthorizations (normalized_email)
WHERE revoked_at IS NULL;

ALTER TABLE public.external_identity_preauthorizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY external_identity_preauthorizations_select_admin
ON public.external_identity_preauthorizations
FOR SELECT
TO authenticated
USING ((SELECT private.can_manage_roles()));

REVOKE ALL ON TABLE public.external_identity_preauthorizations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.external_identity_preauthorizations_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.external_identity_preauthorizations TO authenticated;

CREATE OR REPLACE FUNCTION public.authorize_external_identity(
	email text,
	reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	normalized_target_email text := private.normalize_email(email);
	normalized_reason text := NULLIF(btrim(reason), '');
	new_authorization_id bigint;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_manage_roles() THEN
		RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501';
	END IF;

	IF normalized_target_email IS NULL
		OR normalized_target_email = ''
		OR private.extract_email_domain(normalized_target_email) IS NULL THEN
		RAISE EXCEPTION 'valid external email is required' USING ERRCODE = '23514';
	END IF;

	IF private.is_allowed_email(normalized_target_email) THEN
		RAISE EXCEPTION 'institutional emails cannot be externally preauthorized' USING ERRCODE = '23514';
	END IF;

	IF EXISTS (
		SELECT 1
		FROM public.external_identity_preauthorizations AS preauthorization
		WHERE preauthorization.normalized_email = normalized_target_email
			AND preauthorization.revoked_at IS NULL
	) THEN
		RAISE EXCEPTION 'external identity is already authorized' USING ERRCODE = '23505';
	END IF;

	INSERT INTO public.external_identity_preauthorizations (
		normalized_email,
		authorized_by,
		authorized_at,
		reason
	)
	VALUES (
		normalized_target_email,
		actor_user_id,
		now(),
		normalized_reason
	)
	RETURNING id INTO new_authorization_id;

	RETURN new_authorization_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_external_identity(
	email text,
	reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	normalized_target_email text := private.normalize_email(email);
	normalized_reason text := NULLIF(btrim(reason), '');
	revoked_authorization_id bigint;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_manage_roles() THEN
		RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501';
	END IF;

	IF normalized_target_email IS NULL
		OR normalized_target_email = ''
		OR private.extract_email_domain(normalized_target_email) IS NULL THEN
		RAISE EXCEPTION 'valid external email is required' USING ERRCODE = '23514';
	END IF;

	SELECT preauthorization.id
	INTO revoked_authorization_id
	FROM public.external_identity_preauthorizations AS preauthorization
	WHERE preauthorization.normalized_email = normalized_target_email
		AND preauthorization.revoked_at IS NULL
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'active external identity authorization does not exist' USING ERRCODE = 'P0002';
	END IF;

	UPDATE public.external_identity_preauthorizations
	SET revoked_by = actor_user_id,
		revoked_at = now(),
		revocation_reason = normalized_reason
	WHERE id = revoked_authorization_id;

	RETURN revoked_authorization_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.resolve_admission_identity_kind(email text)
RETURNS public.identity_kind
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	normalized_target_email text := private.normalize_email(email);
BEGIN
	IF normalized_target_email IS NULL
		OR normalized_target_email = ''
		OR private.extract_email_domain(normalized_target_email) IS NULL THEN
		RETURN NULL;
	END IF;

	IF private.is_allowed_email(normalized_target_email) THEN
		RETURN 'institutional'::public.identity_kind;
	END IF;

	IF EXISTS (
		SELECT 1
		FROM public.external_identity_preauthorizations AS preauthorization
		WHERE preauthorization.normalized_email = normalized_target_email
			AND preauthorization.revoked_at IS NULL
	) THEN
		RETURN 'external_authorized'::public.identity_kind;
	END IF;

	RETURN NULL;
END;
$$;

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

	IF TG_OP = 'INSERT'
		OR NEW.email IS DISTINCT FROM OLD.email
		OR NEW.identity_kind IS DISTINCT FROM OLD.identity_kind THEN
		NEW.email := private.normalize_email(NEW.email);

		IF NEW.identity_kind = 'institutional'::public.identity_kind
			AND NOT private.is_allowed_email(NEW.email) THEN
			RAISE EXCEPTION 'institutional profile email domain is not allowed' USING ERRCODE = '23514';
		END IF;
	END IF;

	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_allowed_auth_user_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	normalized_email text := private.normalize_email(NEW.email);
	existing_identity_kind public.identity_kind;
BEGIN
	IF normalized_email IS NULL
		OR normalized_email = ''
		OR private.extract_email_domain(normalized_email) IS NULL THEN
		RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
	END IF;

	IF TG_OP = 'INSERT' THEN
		IF private.resolve_admission_identity_kind(normalized_email) IS NULL THEN
			RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
		END IF;

		RETURN NEW;
	END IF;

	IF private.normalize_email(OLD.email) IS NOT DISTINCT FROM normalized_email THEN
		RETURN NEW;
	END IF;

	SELECT profile.identity_kind
	INTO existing_identity_kind
	FROM public.profiles AS profile
	WHERE profile.user_id = NEW.id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
	END IF;

	IF existing_identity_kind = 'institutional'::public.identity_kind THEN
		IF NOT private.is_allowed_email(normalized_email) THEN
			RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
		END IF;
	ELSIF existing_identity_kind = 'external_authorized'::public.identity_kind THEN
		IF private.resolve_admission_identity_kind(normalized_email)
			IS DISTINCT FROM 'external_authorized'::public.identity_kind THEN
			RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
		END IF;
	ELSE
		RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.sync_auth_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	normalized_email text := private.normalize_email(NEW.email);
	resolved_identity_kind public.identity_kind;
BEGIN
	IF TG_OP = 'INSERT' THEN
		resolved_identity_kind := private.resolve_admission_identity_kind(normalized_email);

		IF resolved_identity_kind IS NULL THEN
			RAISE EXCEPTION 'email is not authorized' USING ERRCODE = '23514';
		END IF;

		INSERT INTO public.profiles (
			user_id,
			email,
			display_name,
			identity_kind,
			account_status
		)
		VALUES (
			NEW.id,
			normalized_email,
			NULL,
			resolved_identity_kind,
			'active'::public.account_status
		)
		ON CONFLICT (user_id) DO UPDATE
		SET email = EXCLUDED.email,
			updated_at = now()
		WHERE public.profiles.email IS DISTINCT FROM EXCLUDED.email;

		RETURN NEW;
	END IF;

	IF TG_OP = 'UPDATE' THEN
		UPDATE public.profiles
		SET email = normalized_email,
			updated_at = now()
		WHERE user_id = NEW.id
			AND email IS DISTINCT FROM normalized_email;

		RETURN NEW;
	END IF;

	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.reconcile_auth_user_profiles()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	invalid_user_count integer;
	colliding_profile_count integer;
BEGIN
	WITH auth_user_emails AS (
		SELECT
			auth_user.id,
			private.normalize_email(auth_user.email) AS normalized_email
		FROM auth.users AS auth_user
	)
	SELECT count(*)::integer
	INTO invalid_user_count
	FROM auth_user_emails
	LEFT JOIN public.profiles AS profile
		ON profile.user_id = auth_user_emails.id
	WHERE auth_user_emails.normalized_email IS NULL
		OR auth_user_emails.normalized_email = ''
		OR private.extract_email_domain(auth_user_emails.normalized_email) IS NULL
		OR (
			profile.user_id IS NULL
			AND private.resolve_admission_identity_kind(auth_user_emails.normalized_email) IS NULL
		)
		OR (
			profile.identity_kind = 'institutional'::public.identity_kind
			AND NOT private.is_allowed_email(auth_user_emails.normalized_email)
		)
		OR (
			profile.identity_kind = 'external_authorized'::public.identity_kind
			AND profile.email IS DISTINCT FROM auth_user_emails.normalized_email
			AND private.resolve_admission_identity_kind(auth_user_emails.normalized_email)
				IS DISTINCT FROM 'external_authorized'::public.identity_kind
		);

	IF invalid_user_count > 0 THEN
		RAISE EXCEPTION 'auth user profile reconciliation requires authorized emails'
			USING ERRCODE = '23514';
	END IF;

	WITH auth_user_emails AS (
		SELECT
			auth_user.id,
			private.normalize_email(auth_user.email) AS normalized_email
		FROM auth.users AS auth_user
	)
	SELECT count(*)::integer
	INTO colliding_profile_count
	FROM auth_user_emails
	INNER JOIN public.profiles AS profile
		ON profile.email = auth_user_emails.normalized_email
		AND profile.user_id <> auth_user_emails.id;

	IF colliding_profile_count > 0 THEN
		RAISE EXCEPTION 'auth user profile reconciliation conflict'
			USING ERRCODE = '23505';
	END IF;

	INSERT INTO public.profiles (
		user_id,
		email,
		display_name,
		identity_kind,
		account_status
	)
	SELECT
		auth_user.id,
		private.normalize_email(auth_user.email),
		NULL,
		COALESCE(
			existing_profile.identity_kind,
			private.resolve_admission_identity_kind(auth_user.email)
		),
		'active'::public.account_status
	FROM auth.users AS auth_user
	LEFT JOIN public.profiles AS existing_profile
		ON existing_profile.user_id = auth_user.id
	ON CONFLICT (user_id) DO UPDATE
	SET email = EXCLUDED.email,
		updated_at = pg_catalog.now()
	WHERE public.profiles.email IS DISTINCT FROM EXCLUDED.email;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_external_identity(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_external_identity(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.resolve_admission_identity_kind(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.enforce_allowed_auth_user_email() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.sync_auth_user_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.reconcile_auth_user_profiles() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.authorize_external_identity(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_external_identity(text, text) TO authenticated;

COMMIT;
