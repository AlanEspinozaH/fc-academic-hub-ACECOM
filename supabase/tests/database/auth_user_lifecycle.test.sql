SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT plan(37);

CREATE OR REPLACE FUNCTION pg_temp.try_insert_auth_user(target_user_id uuid, email_address text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
	INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
	VALUES (target_user_id, 'authenticated', 'authenticated', email_address, now(), now(), now());

	RETURN true;
EXCEPTION
	WHEN OTHERS THEN
		RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.try_update_auth_user_email(target_user_id uuid, email_address text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
	UPDATE auth.users
	SET email = email_address,
		updated_at = now()
	WHERE id = target_user_id;

	RETURN true;
EXCEPTION
	WHEN OTHERS THEN
		RETURN false;
END;
$$;

CREATE TEMP TABLE lifecycle_test_user_ids (id uuid PRIMARY KEY);

INSERT INTO lifecycle_test_user_ids (id)
VALUES
	('00000000-0000-0000-0000-000000000301'),
	('00000000-0000-0000-0000-000000000302'),
	('00000000-0000-0000-0000-000000000303'),
	('00000000-0000-0000-0000-000000000310'),
	('00000000-0000-0000-0000-000000000320'),
	('00000000-0000-0000-0000-000000000330'),
	('00000000-0000-0000-0000-000000000391'),
	('00000000-0000-0000-0000-000000000392'),
	('00000000-0000-0000-0000-000000000393'),
	('00000000-0000-0000-0000-000000000394'),
	('00000000-0000-0000-0000-000000000395'),
	('00000000-0000-0000-0000-000000000396'),
	('00000000-0000-0000-0000-000000000397');

SELECT ok(
	to_regprocedure('private.enforce_allowed_auth_user_email()') IS NOT NULL,
	'enforce_allowed_auth_user_email exists'
);
SELECT ok(
	to_regprocedure('private.sync_auth_user_profile()') IS NOT NULL,
	'sync_auth_user_profile exists'
);
SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_trigger
		WHERE tgrelid = 'auth.users'::regclass
			AND tgname = 'auth_users_stage_3b1_enforce_allowed_email'
			AND NOT tgisinternal
	),
	'enforce auth email trigger exists'
);
SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_trigger
		WHERE tgrelid = 'auth.users'::regclass
			AND tgname = 'auth_users_stage_3b1_sync_profile'
			AND NOT tgisinternal
	),
	'sync profile trigger exists'
);
SELECT ok(
	(
		WITH expected(function_name) AS (
			VALUES
				('enforce_allowed_auth_user_email'),
				('sync_auth_user_profile')
		),
		function_settings AS (
			SELECT
				pg_proc.prosecdef,
				EXISTS (
					SELECT 1
					FROM unnest(COALESCE(pg_proc.proconfig, ARRAY[]::text[])) AS function_setting(setting)
					WHERE replace(function_setting.setting, 'search_path=', '') IN ('', '""')
				) AS has_empty_search_path
			FROM expected
			INNER JOIN pg_namespace
				ON pg_namespace.nspname = 'private'
			INNER JOIN pg_proc
				ON pg_proc.pronamespace = pg_namespace.oid
				AND pg_proc.proname = expected.function_name
		)
		SELECT count(*) = 2
			AND bool_and(prosecdef)
			AND bool_and(has_empty_search_path)
		FROM function_settings
	),
	'lifecycle trigger functions are SECURITY DEFINER with empty search_path'
);
SELECT ok(
	NOT EXISTS (
		WITH lifecycle_functions AS (
			SELECT pg_proc.oid, pg_proc.proacl, pg_proc.proowner
			FROM pg_namespace
			INNER JOIN pg_proc
				ON pg_proc.pronamespace = pg_namespace.oid
			WHERE pg_namespace.nspname = 'private'
				AND pg_proc.proname IN (
					'enforce_allowed_auth_user_email',
					'sync_auth_user_profile'
				)
		)
		SELECT 1
		FROM lifecycle_functions
		CROSS JOIN LATERAL aclexplode(
			COALESCE(lifecycle_functions.proacl, acldefault('f', lifecycle_functions.proowner))
		) AS function_acl
		WHERE function_acl.grantee = 0::oid
			AND function_acl.privilege_type = 'EXECUTE'
	),
	'PUBLIC cannot execute lifecycle trigger functions directly'
);
SELECT ok(
	NOT EXISTS (
		WITH lifecycle_functions AS (
			SELECT pg_proc.oid, pg_proc.proacl, pg_proc.proowner
			FROM pg_namespace
			INNER JOIN pg_proc
				ON pg_proc.pronamespace = pg_namespace.oid
			WHERE pg_namespace.nspname = 'private'
				AND pg_proc.proname IN (
					'enforce_allowed_auth_user_email',
					'sync_auth_user_profile'
				)
		)
		SELECT 1
		FROM lifecycle_functions
		CROSS JOIN LATERAL aclexplode(
			COALESCE(lifecycle_functions.proacl, acldefault('f', lifecycle_functions.proowner))
		) AS function_acl
		WHERE function_acl.grantee IN ('anon'::regrole::oid, 'authenticated'::regrole::oid)
			AND function_acl.privilege_type = 'EXECUTE'
	),
	'anon and authenticated cannot execute lifecycle trigger functions directly'
);

SELECT ok(
	pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000301',
		'usuario@uni.pe'
	),
	'INSERT usuario@uni.pe works'
);
SELECT ok(
	pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000302',
		'MAYUSCULA@UNI.PE'
	),
	'INSERT with uppercase institutional email works'
);

INSERT INTO auth.users (
	id,
	aud,
	role,
	email,
	raw_user_meta_data,
	raw_app_meta_data,
	email_confirmed_at,
	created_at,
	updated_at
)
VALUES (
	'00000000-0000-0000-0000-000000000303',
	'authenticated',
	'authenticated',
	'metadata@uni.pe',
	'{"display_name": "Metadata Name", "avatar_url": "https://example.invalid/avatar.png"}'::jsonb,
	'{"provider": "google"}'::jsonb,
	now(),
	now(),
	now()
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000301'
	),
	1,
	'profile is created automatically'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000302'
	),
	'mayuscula@uni.pe',
	'profile email is normalized'
);
SELECT is(
	(
		SELECT display_name
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000301'
	),
	NULL::text,
	'profile display_name defaults to null'
);
SELECT is(
	(
		SELECT account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000301'
	),
	'active',
	'profile account_status defaults to active'
);
SELECT is(
	(
		SELECT display_name
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000303'
	),
	NULL::text,
	'raw user metadata is not copied into display_name'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.user_roles
		WHERE user_id IN (
			'00000000-0000-0000-0000-000000000301',
			'00000000-0000-0000-0000-000000000302',
			'00000000-0000-0000-0000-000000000303'
		)
	),
	0,
	'no user_role is created automatically'
);

SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000391',
		'usuario@falsauni.pe'
	),
	'falsauni.pe is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000392',
		'usuario@uni.pe.example.com'
	),
	'uni.pe.example.com is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000393',
		'usuario@exampleuni.pe'
	),
	'exampleuni.pe is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000394',
		'usuario@subdominio.uni.pe'
	),
	'subdominio.uni.pe is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000395',
		'usuario@'
	),
	'empty email domain is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000396',
		'texto-sin-arroba'
	),
	'email without at sign is rejected'
);
SELECT ok(
	NOT pg_temp.try_insert_auth_user(
		'00000000-0000-0000-0000-000000000397',
		NULL::text
	),
	'null email is rejected'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM auth.users
		WHERE id IN (
			'00000000-0000-0000-0000-000000000391',
			'00000000-0000-0000-0000-000000000392',
			'00000000-0000-0000-0000-000000000393',
			'00000000-0000-0000-0000-000000000394',
			'00000000-0000-0000-0000-000000000395',
			'00000000-0000-0000-0000-000000000396',
			'00000000-0000-0000-0000-000000000397'
		)
	),
	0,
	'failed inserts leave no auth.users rows'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id IN (
			'00000000-0000-0000-0000-000000000391',
			'00000000-0000-0000-0000-000000000392',
			'00000000-0000-0000-0000-000000000393',
			'00000000-0000-0000-0000-000000000394',
			'00000000-0000-0000-0000-000000000395',
			'00000000-0000-0000-0000-000000000396',
			'00000000-0000-0000-0000-000000000397'
		)
	),
	0,
	'failed inserts leave no partial profiles'
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000310',
	'authenticated',
	'authenticated',
	'cambio-inicial@uni.pe',
	now(),
	now(),
	now()
);

UPDATE public.profiles
SET display_name = 'Nombre preservado',
	account_status = 'suspended'::public.account_status
WHERE user_id = '00000000-0000-0000-0000-000000000310';

SELECT ok(
	pg_temp.try_update_auth_user_email(
		'00000000-0000-0000-0000-000000000310',
		'cambio-final@uni.pe'
	),
	'changing auth.users email to another uni.pe address works'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000310'
	),
	'cambio-final@uni.pe',
	'profile email follows auth.users email changes'
);
SELECT ok(
	NOT pg_temp.try_update_auth_user_email(
		'00000000-0000-0000-0000-000000000310',
		'cambio@falsauni.pe'
	),
	'changing auth.users email to an invalid domain is rejected'
);
SELECT is(
	(
		SELECT email
		FROM auth.users
		WHERE id = '00000000-0000-0000-0000-000000000310'
	),
	'cambio-final@uni.pe',
	'rejected email change preserves previous auth.users email'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000310'
	),
	'cambio-final@uni.pe',
	'rejected email change preserves previous profile email'
);
SELECT is(
	(
		SELECT display_name
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000310'
	),
	'Nombre preservado',
	'email change does not alter display_name'
);
SELECT is(
	(
		SELECT account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000310'
	),
	'suspended',
	'email change does not alter account_status'
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000320',
	'authenticated',
	'authenticated',
	'cascade@uni.pe',
	now(),
	now(),
	now()
);

DELETE FROM auth.users
WHERE id = '00000000-0000-0000-0000-000000000320';

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000320'
	),
	0,
	'deleting auth.users cascades to profiles'
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000330',
	'authenticated',
	'authenticated',
	'backfill@uni.pe',
	now(),
	now(),
	now()
);

UPDATE public.profiles
SET display_name = 'Perfil existente',
	account_status = 'disabled'::public.account_status
WHERE user_id = '00000000-0000-0000-0000-000000000330';

CREATE TEMP TABLE backfill_profile_snapshot AS
SELECT user_id, created_at
FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000330';

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
WHERE auth_user.id = '00000000-0000-0000-0000-000000000330'
ON CONFLICT (user_id) DO NOTHING;

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000330'
	),
	1,
	're-running the backfill does not create duplicate profiles'
);
SELECT is(
	(
		SELECT display_name
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000330'
	),
	'Perfil existente',
	'backfill preserves existing display_name'
);
SELECT is(
	(
		SELECT account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000330'
	),
	'disabled',
	'backfill preserves existing account_status'
);
SELECT is(
	(
		SELECT created_at
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000330'
	),
	(
		SELECT created_at
		FROM backfill_profile_snapshot
		WHERE user_id = '00000000-0000-0000-0000-000000000330'
	),
	'backfill preserves existing created_at'
);
SELECT is(
	(
		(
			SELECT count(*)
			FROM public.user_roles
			WHERE user_id IN (SELECT id FROM lifecycle_test_user_ids)
				OR granted_by IN (SELECT id FROM lifecycle_test_user_ids)
		)::integer
		+
		(
			SELECT count(*)
			FROM public.role_audit_log
			WHERE actor_user_id IN (SELECT id FROM lifecycle_test_user_ids)
				OR target_user_id IN (SELECT id FROM lifecycle_test_user_ids)
		)::integer
	),
	0,
	'lifecycle and backfill create no roles or role audit entries'
);

SELECT * FROM finish();

ROLLBACK;
