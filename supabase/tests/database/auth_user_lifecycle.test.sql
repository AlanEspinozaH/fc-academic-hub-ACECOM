SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT plan(77);

CREATE TEMP TABLE lifecycle_test_user_ids (id uuid PRIMARY KEY);

INSERT INTO lifecycle_test_user_ids (id)
VALUES
	('00000000-0000-0000-0000-000000000301'),
	('00000000-0000-0000-0000-000000000302'),
	('00000000-0000-0000-0000-000000000303'),
	('00000000-0000-0000-0000-000000000310'),
	('00000000-0000-0000-0000-000000000320'),
	('00000000-0000-0000-0000-000000000330'),
	('00000000-0000-0000-0000-000000000331'),
	('00000000-0000-0000-0000-000000000332'),
	('00000000-0000-0000-0000-000000000333'),
	('00000000-0000-0000-0000-000000000334'),
	('00000000-0000-0000-0000-000000000335'),
	('00000000-0000-0000-0000-000000000336'),
	('00000000-0000-0000-0000-000000000340'),
	('00000000-0000-0000-0000-000000000341'),
	('00000000-0000-0000-0000-000000000342'),
	('00000000-0000-0000-0000-000000000343'),
	('00000000-0000-0000-0000-000000000344'),
	('00000000-0000-0000-0000-000000000345'),
	('00000000-0000-0000-0000-000000000391'),
	('00000000-0000-0000-0000-000000000392'),
	('00000000-0000-0000-0000-000000000393'),
	('00000000-0000-0000-0000-000000000394'),
	('00000000-0000-0000-0000-000000000395'),
	('00000000-0000-0000-0000-000000000396'),
	('00000000-0000-0000-0000-000000000397'),
	('00000000-0000-0000-0000-000000000398');

SELECT ok(
	to_regprocedure('private.enforce_allowed_auth_user_email()') IS NOT NULL,
	'enforce_allowed_auth_user_email exists'
);
SELECT ok(
	to_regprocedure('private.sync_auth_user_profile()') IS NOT NULL,
	'sync_auth_user_profile exists'
);
SELECT ok(
	to_regprocedure('private.reconcile_auth_user_profiles()') IS NOT NULL,
	'reconcile_auth_user_profiles exists'
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
				('sync_auth_user_profile'),
				('reconcile_auth_user_profiles')
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
		SELECT count(*) = 3
			AND bool_and(prosecdef)
			AND bool_and(has_empty_search_path)
		FROM function_settings
	),
	'private lifecycle functions are SECURITY DEFINER with empty search_path'
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
					'sync_auth_user_profile',
					'reconcile_auth_user_profiles'
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
	'PUBLIC cannot execute private lifecycle functions directly'
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
					'sync_auth_user_profile',
					'reconcile_auth_user_profiles'
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
	'anon and authenticated cannot execute private lifecycle functions directly'
);

SELECT lives_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000301',
			'authenticated',
			'authenticated',
			'usuario@uni.pe',
			now(),
			now(),
			now()
		)
	$$,
	'INSERT usuario@uni.pe works'
);
SELECT lives_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000302',
			'authenticated',
			'authenticated',
			'MAYUSCULA@UNI.PE',
			now(),
			now(),
			now()
		)
	$$,
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
		SELECT identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000301'
	),
	'institutional',
	'new institutional account defaults to institutional identity_kind'
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

SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000340',
			'authenticated',
			'authenticated',
			'random@example.com',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'random external email without preauthorization is rejected'
);

INSERT INTO public.external_identity_preauthorizations (
	normalized_email,
	authorized_by,
	reason
)
VALUES (
	'persona@example.com',
	'00000000-0000-0000-0000-000000000301',
	'lifecycle exact-email fixture'
);

SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000341',
			'authenticated',
			'authenticated',
			'otra@example.com',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'preauthorization does not authorize another email in the same domain'
);

SELECT lives_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000342',
			'authenticated',
			'authenticated',
			'PERSONA@EXAMPLE.COM',
			now(),
			now(),
			now()
		)
	$$,
	'exact normalized preauthorization permits external signup'
);
SELECT is(
	(
		SELECT identity_kind::text || ':' || account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000342'
			AND email = 'persona@example.com'
	),
	'external_authorized:active',
	'preauthorized signup creates an active external_authorized profile'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.user_roles
		WHERE user_id = '00000000-0000-0000-0000-000000000342'
	),
	0,
	'external signup creates no roles'
);

INSERT INTO public.external_identity_preauthorizations (
	normalized_email,
	authorized_by,
	reason,
	revoked_by,
	revoked_at,
	revocation_reason
)
VALUES (
	'revoked-before@example.net',
	'00000000-0000-0000-0000-000000000301',
	'before materialization fixture',
	'00000000-0000-0000-0000-000000000301',
	now(),
	'revoked before signup'
);

SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000343',
			'authenticated',
			'authenticated',
			'revoked-before@example.net',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'revocation before materialization prevents signup'
);

UPDATE public.external_identity_preauthorizations
SET revoked_by = '00000000-0000-0000-0000-000000000301',
	revoked_at = now(),
	revocation_reason = 'revoked after materialization'
WHERE normalized_email = 'persona@example.com'
	AND revoked_at IS NULL;

SELECT is(
	(
		SELECT identity_kind::text || ':' || account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000342'
	),
	'external_authorized:active',
	'revocation after materialization preserves profile identity and status'
);
SELECT lives_ok(
	$$
		UPDATE auth.users
		SET email = ' persona@example.com ',
			updated_at = now()
		WHERE id = '00000000-0000-0000-0000-000000000342'
	$$,
	'same normalized external email remains valid after preauthorization revocation'
);
SELECT lives_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'reconciliation accepts a materialized external identity after preauthorization revocation'
);
SELECT throws_ok(
	$$
		UPDATE auth.users
		SET email = 'persona@uni.pe',
			updated_at = now()
		WHERE id = '00000000-0000-0000-0000-000000000342'
	$$,
	'23514',
	'email is not authorized',
	'a materialized external identity cannot change to an institutional email'
);
SELECT is(
	(
		SELECT email || ':' || identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000342'
	),
	'persona@example.com:external_authorized',
	'rejected institutional change preserves the external profile email and identity_kind'
);

INSERT INTO public.external_identity_preauthorizations (normalized_email, authorized_by, reason)
VALUES (
	'persona-next@example.com',
	'00000000-0000-0000-0000-000000000301',
	'external email change fixture'
);
SELECT lives_ok(
	$$
		UPDATE auth.users
		SET email = 'PERSONA-NEXT@EXAMPLE.COM',
			updated_at = now()
		WHERE id = '00000000-0000-0000-0000-000000000342'
	$$,
	'a materialized external identity can change to an exactly preauthorized external email'
);
SELECT is(
	(
		SELECT email || ':' || identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000342'
	),
	'persona-next@example.com:external_authorized',
	'authorized external email change updates the profile while preserving identity_kind'
);

UPDATE public.profiles
SET email = 'persona@example.com'
WHERE user_id = '00000000-0000-0000-0000-000000000342';
UPDATE public.external_identity_preauthorizations
SET revoked_by = '00000000-0000-0000-0000-000000000301',
	revoked_at = now(),
	revocation_reason = 'reconciliation mismatch fixture'
WHERE normalized_email = 'persona-next@example.com'
	AND revoked_at IS NULL;
SELECT throws_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'23514',
	'auth user profile reconciliation requires authorized emails',
	'reconciliation rejects an external profile email mismatch without active exact preauthorization'
);
UPDATE public.profiles
SET email = 'persona-next@example.com'
WHERE user_id = '00000000-0000-0000-0000-000000000342';

INSERT INTO public.external_identity_preauthorizations (normalized_email, authorized_by, reason)
VALUES (
	'missing-active@example.org',
	'00000000-0000-0000-0000-000000000301',
	'active missing-profile fixture'
);
INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000344',
	'authenticated',
	'authenticated',
	'missing-active@example.org',
	now(),
	now(),
	now()
);
DELETE FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000344';
SELECT lives_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'reconciliation recreates a missing external profile with active exact preauthorization'
);
SELECT is(
	(
		SELECT identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000344'
	),
	'external_authorized',
	'recreated external profile keeps external_authorized identity_kind'
);

INSERT INTO public.external_identity_preauthorizations (normalized_email, authorized_by, reason)
VALUES (
	'missing-revoked@example.org',
	'00000000-0000-0000-0000-000000000301',
	'revoked missing-profile fixture'
);
INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000345',
	'authenticated',
	'authenticated',
	'missing-revoked@example.org',
	now(),
	now(),
	now()
);
DELETE FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000345';
UPDATE public.external_identity_preauthorizations
SET revoked_by = '00000000-0000-0000-0000-000000000301',
	revoked_at = now(),
	revocation_reason = 'revoked before reconciliation'
WHERE normalized_email = 'missing-revoked@example.org'
	AND revoked_at IS NULL;
SELECT throws_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'23514',
	'auth user profile reconciliation requires authorized emails',
	'missing external profile cannot be recreated without active exact preauthorization'
);
DELETE FROM auth.users
WHERE id = '00000000-0000-0000-0000-000000000345';

SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000391',
			'authenticated',
			'authenticated',
			'usuario@falsauni.pe',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'falsauni.pe is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000392',
			'authenticated',
			'authenticated',
			'usuario@uni.pe.example.com',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'uni.pe.example.com is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000393',
			'authenticated',
			'authenticated',
			'usuario@exampleuni.pe',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'exampleuni.pe is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000394',
			'authenticated',
			'authenticated',
			'usuario@subdominio.uni.pe',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'subdominio.uni.pe is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000395',
			'authenticated',
			'authenticated',
			'usuario@',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'empty email domain is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000396',
			'authenticated',
			'authenticated',
			'texto-sin-arroba',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'email without at sign is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000397',
			'authenticated',
			'authenticated',
			NULL,
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'null email is rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
		VALUES (
			'00000000-0000-0000-0000-000000000398',
			'authenticated',
			'authenticated',
			'',
			now(),
			now(),
			now()
		)
	$$,
	'23514',
	'email is not authorized',
	'empty literal email is rejected'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM auth.users
		WHERE id = '00000000-0000-0000-0000-000000000398'
	),
	0,
	'failed empty literal insert leaves no auth.users row'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000398'
	),
	0,
	'failed empty literal insert leaves no profile'
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

SELECT lives_ok(
	$$
		UPDATE auth.users
		SET email = 'cambio-final@uni.pe',
			updated_at = now()
		WHERE id = '00000000-0000-0000-0000-000000000310'
	$$,
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
SELECT throws_ok(
	$$
		UPDATE auth.users
		SET email = 'cambio@falsauni.pe',
			updated_at = now()
		WHERE id = '00000000-0000-0000-0000-000000000310'
	$$,
	'23514',
	'email is not authorized',
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
SELECT is(
	(
		SELECT identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000310'
	),
	'institutional',
	'email change preserves identity_kind'
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

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000331',
	'authenticated',
	'authenticated',
	'reconcile-missing@uni.pe',
	now(),
	now(),
	now()
);

DELETE FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000331';

INSERT INTO public.external_identity_preauthorizations (
	normalized_email,
	authorized_by,
	reason
)
VALUES (
	'reconcile-current@example.com',
	'00000000-0000-0000-0000-000000000301',
	'reconciliation external identity fixture'
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000332',
	'authenticated',
	'authenticated',
	'reconcile-current@example.com',
	now(),
	now(),
	now()
);

DELETE FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000332';

INSERT INTO public.profiles (
	user_id,
	email,
	display_name,
	identity_kind,
	account_status,
	created_at,
	updated_at
)
VALUES (
	'00000000-0000-0000-0000-000000000332',
	'reconcile-obsolete@example.com',
	'Perfil reconciliado',
	'external_authorized'::public.identity_kind,
	'suspended'::public.account_status,
	'2026-01-01 00:00:00+00'::timestamptz,
	'2026-01-02 00:00:00+00'::timestamptz
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES (
	'00000000-0000-0000-0000-000000000333',
	'authenticated',
	'authenticated',
	'reconcile-stable@uni.pe',
	now(),
	now(),
	now()
);

DELETE FROM public.profiles
WHERE user_id = '00000000-0000-0000-0000-000000000333';

INSERT INTO public.profiles (
	user_id,
	email,
	display_name,
	account_status,
	created_at,
	updated_at
)
VALUES (
	'00000000-0000-0000-0000-000000000333',
	'reconcile-stable@uni.pe',
	'Perfil estable',
	'disabled'::public.account_status,
	'2026-02-01 00:00:00+00'::timestamptz,
	'2026-02-02 00:00:00+00'::timestamptz
);

CREATE TEMP TABLE reconcile_profile_snapshot AS
SELECT user_id, created_at, updated_at
FROM public.profiles
WHERE user_id IN (
	'00000000-0000-0000-0000-000000000332',
	'00000000-0000-0000-0000-000000000333'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000331'
	),
	0,
	'reconciliation setup has a missing profile'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'reconcile-obsolete@example.com',
	'reconciliation setup has an obsolete profile email'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000333'
	),
	'reconcile-stable@uni.pe',
	'reconciliation setup has a matching profile email'
);
SELECT lives_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'reconcile_auth_user_profiles runs without collisions'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000331'
			AND email = 'reconcile-missing@uni.pe'
	),
	1,
	'reconcile_auth_user_profiles recreates a missing profile'
);
SELECT is(
	(
		SELECT identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000331'
	),
	'institutional',
	'reconcile_auth_user_profiles defaults a missing profile to institutional'
);
SELECT is(
	(
		SELECT email
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'reconcile-current@example.com',
	'reconcile_auth_user_profiles corrects an obsolete profile email'
);
SELECT is(
	(
		SELECT display_name
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'Perfil reconciliado',
	'reconciliation preserves display_name'
);
SELECT is(
	(
		SELECT account_status::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'suspended',
	'reconciliation preserves account_status'
);
SELECT is(
	(
		SELECT identity_kind::text
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'external_authorized',
	'reconciliation preserves existing identity_kind'
);
SELECT is(
	(
		SELECT created_at
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	(
		SELECT created_at
		FROM reconcile_profile_snapshot
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'reconciliation preserves created_at'
);
SELECT isnt(
	(
		SELECT updated_at
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	(
		SELECT updated_at
		FROM reconcile_profile_snapshot
		WHERE user_id = '00000000-0000-0000-0000-000000000332'
	),
	'reconciliation changes updated_at when email changes'
);
SELECT is(
	(
		SELECT updated_at
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000333'
	),
	(
		SELECT updated_at
		FROM reconcile_profile_snapshot
		WHERE user_id = '00000000-0000-0000-0000-000000000333'
	),
	'reconciliation preserves updated_at when email already matches'
);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES
	(
		'00000000-0000-0000-0000-000000000334',
		'authenticated',
		'authenticated',
		'reconcile-collision@uni.pe',
		now(),
		now(),
		now()
	),
	(
		'00000000-0000-0000-0000-000000000335',
		'authenticated',
		'authenticated',
		'reconcile-holder@uni.pe',
		now(),
		now(),
		now()
	),
	(
		'00000000-0000-0000-0000-000000000336',
		'authenticated',
		'authenticated',
		'reconcile-unrelated-missing@uni.pe',
		now(),
		now(),
		now()
	);

DELETE FROM public.profiles
WHERE user_id IN (
	'00000000-0000-0000-0000-000000000334',
	'00000000-0000-0000-0000-000000000336'
);

UPDATE public.profiles
SET email = 'reconcile-collision@uni.pe'
WHERE user_id = '00000000-0000-0000-0000-000000000335';

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id <> '00000000-0000-0000-0000-000000000334'
			AND email = 'reconcile-collision@uni.pe'
	),
	1,
	'reconciliation collision setup assigns the auth email to another profile'
);
SELECT throws_ok(
	$$ SELECT private.reconcile_auth_user_profiles() $$,
	'23505',
	'auth user profile reconciliation conflict',
	'email collision aborts profile reconciliation'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000334'
	),
	0,
	'collision failure does not recreate the colliding missing profile'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000336'
	),
	0,
	'collision failure leaves unrelated missing profiles unchanged'
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
