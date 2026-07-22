BEGIN;

CREATE OR REPLACE FUNCTION private.enforce_allowed_auth_user_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	normalized_email text := private.normalize_email(NEW.email);
BEGIN
	IF normalized_email IS NULL OR normalized_email = '' THEN
		RAISE EXCEPTION 'institutional email is required' USING ERRCODE = '23514';
	END IF;

	IF private.extract_email_domain(normalized_email) IS NULL THEN
		RAISE EXCEPTION 'institutional email is required' USING ERRCODE = '23514';
	END IF;

	IF NOT private.is_allowed_email(normalized_email) THEN
		RAISE EXCEPTION 'institutional email is required' USING ERRCODE = '23514';
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
BEGIN
	IF normalized_email IS NULL
		OR normalized_email = ''
		OR private.extract_email_domain(normalized_email) IS NULL
		OR NOT private.is_allowed_email(normalized_email) THEN
		RAISE EXCEPTION 'institutional email is required' USING ERRCODE = '23514';
	END IF;

	IF TG_OP = 'INSERT' THEN
		INSERT INTO public.profiles (
			user_id,
			email,
			display_name,
			account_status
		)
		VALUES (
			NEW.id,
			normalized_email,
			NULL,
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
		WHERE user_id = NEW.id;

		RETURN NEW;
	END IF;

	RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_allowed_auth_user_email() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.sync_auth_user_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS auth_users_stage_3b1_enforce_allowed_email ON auth.users;
CREATE TRIGGER auth_users_stage_3b1_enforce_allowed_email
BEFORE INSERT OR UPDATE OF email ON auth.users
FOR EACH ROW
EXECUTE FUNCTION private.enforce_allowed_auth_user_email();

DROP TRIGGER IF EXISTS auth_users_stage_3b1_sync_profile ON auth.users;
CREATE TRIGGER auth_users_stage_3b1_sync_profile
AFTER INSERT OR UPDATE OF email ON auth.users
FOR EACH ROW
EXECUTE FUNCTION private.sync_auth_user_profile();

DO $$
DECLARE
	invalid_user_count integer;
BEGIN
	SELECT count(*)::integer
	INTO invalid_user_count
	FROM auth.users AS auth_user
	WHERE auth_user.email IS NULL
		OR private.normalize_email(auth_user.email) = ''
		OR private.extract_email_domain(auth_user.email) IS NULL
		OR NOT private.is_allowed_email(auth_user.email);

	IF invalid_user_count > 0 THEN
		RAISE EXCEPTION 'existing auth users must use an institutional email before profile lifecycle can be enabled'
			USING ERRCODE = '23514';
	END IF;
END;
$$;

INSERT INTO public.profiles (
	user_id,
	email,
	display_name,
	account_status
)
SELECT
	auth_user.id,
	private.normalize_email(auth_user.email),
	NULL,
	'active'::public.account_status
FROM auth.users AS auth_user
ON CONFLICT (user_id) DO NOTHING;

COMMIT;
