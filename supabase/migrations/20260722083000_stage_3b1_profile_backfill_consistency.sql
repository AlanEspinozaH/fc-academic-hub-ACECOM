BEGIN;

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
	WHERE normalized_email IS NULL
		OR normalized_email = ''
		OR private.extract_email_domain(normalized_email) IS NULL
		OR NOT private.is_allowed_email(normalized_email);

	IF invalid_user_count > 0 THEN
		RAISE EXCEPTION 'auth user profile reconciliation requires valid institutional emails'
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
		account_status
	)
	SELECT
		auth_user.id,
		private.normalize_email(auth_user.email),
		NULL,
		'active'::public.account_status
	FROM auth.users AS auth_user
	ON CONFLICT (user_id) DO UPDATE
	SET email = EXCLUDED.email,
		updated_at = pg_catalog.now()
	WHERE public.profiles.email IS DISTINCT FROM EXCLUDED.email;
END;
$$;

REVOKE ALL ON FUNCTION private.reconcile_auth_user_profiles() FROM PUBLIC, anon, authenticated;

SELECT private.reconcile_auth_user_profiles();

COMMIT;
