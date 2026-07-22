SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT plan(47);

CREATE OR REPLACE FUNCTION pg_temp.set_request_context(user_id uuid, jwt_role text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
	claims jsonb := jsonb_build_object('role', jwt_role);
BEGIN
	IF user_id IS NOT NULL THEN
		claims := claims || jsonb_build_object('sub', user_id::text);
	END IF;

	PERFORM set_config('request.jwt.claims', claims::text, true);
	PERFORM set_config('request.jwt.claim.sub', COALESCE(user_id::text, ''), true);
	PERFORM set_config('request.jwt.claim.role', jwt_role, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.try_sql(statement text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
	EXECUTE statement;
	RETURN true;
EXCEPTION
	WHEN OTHERS THEN
		RETURN false;
END;
$$;

CREATE TEMP TABLE test_users (
	kind text PRIMARY KEY,
	id uuid NOT NULL,
	email text NOT NULL
);

INSERT INTO test_users (kind, id, email)
VALUES
	('student', '00000000-0000-0000-0000-000000000101', 'stage3a1-student@uni.pe'),
	('contributor', '00000000-0000-0000-0000-000000000102', 'stage3a1-contributor@uni.pe'),
	('reviewer', '00000000-0000-0000-0000-000000000103', 'stage3a1-reviewer@uni.pe'),
	('moderator', '00000000-0000-0000-0000-000000000104', 'stage3a1-moderator@uni.pe'),
	('administrator', '00000000-0000-0000-0000-000000000105', 'stage3a1-admin@uni.pe'),
	('target', '00000000-0000-0000-0000-000000000106', 'stage3a1-target@uni.pe'),
	('other', '00000000-0000-0000-0000-000000000107', 'stage3a1-other@uni.pe');

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
SELECT id, 'authenticated', 'authenticated', email, now(), now(), now()
FROM test_users;

INSERT INTO public.profiles (user_id, email, display_name)
SELECT id, email, kind
FROM test_users;

INSERT INTO public.user_roles (user_id, role, granted_by, granted_at, revoked_by, revoked_at, reason)
VALUES
	(
		'00000000-0000-0000-0000-000000000105',
		'administrator',
		'00000000-0000-0000-0000-000000000105',
		now(),
		NULL,
		NULL,
		'test administrator bootstrap'
	),
	(
		'00000000-0000-0000-0000-000000000101',
		'student',
		'00000000-0000-0000-0000-000000000105',
		now(),
		NULL,
		NULL,
		'test student role'
	),
	(
		'00000000-0000-0000-0000-000000000102',
		'contributor',
		'00000000-0000-0000-0000-000000000105',
		now(),
		NULL,
		NULL,
		'test contributor role'
	),
	(
		'00000000-0000-0000-0000-000000000103',
		'reviewer',
		'00000000-0000-0000-0000-000000000105',
		now(),
		NULL,
		NULL,
		'test reviewer role'
	),
	(
		'00000000-0000-0000-0000-000000000104',
		'moderator',
		'00000000-0000-0000-0000-000000000105',
		now(),
		NULL,
		NULL,
		'test moderator role'
	),
	(
		'00000000-0000-0000-0000-000000000101',
		'contributor',
		'00000000-0000-0000-0000-000000000105',
		now() - interval '2 days',
		'00000000-0000-0000-0000-000000000105',
		now() - interval '1 day',
		'test revoked role'
	);

SELECT ok(to_regclass('public.allowed_email_domains') IS NOT NULL, 'allowed_email_domains exists');
SELECT ok(to_regclass('public.profiles') IS NOT NULL, 'profiles exists');
SELECT ok(to_regclass('public.user_roles') IS NOT NULL, 'user_roles exists');
SELECT ok(to_regclass('public.role_audit_log') IS NOT NULL, 'role_audit_log exists');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.allowed_email_domains'::regclass), 'allowed_email_domains has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.profiles'::regclass), 'profiles has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.user_roles'::regclass), 'user_roles has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.role_audit_log'::regclass), 'role_audit_log has RLS enabled');

SELECT is(
	(SELECT enabled FROM public.allowed_email_domains WHERE domain = 'uni.pe'),
	true,
	'uni.pe is enabled'
);
SELECT ok(private.is_allowed_email('usuario@uni.pe'), 'usuario@uni.pe is valid');
SELECT is(private.normalize_email(' USUARIO@UNI.PE '), 'usuario@uni.pe', 'uppercase email is normalized');
SELECT ok(private.is_allowed_email('USUARIO@UNI.PE'), 'uppercase institutional email is valid');
SELECT ok(NOT private.is_allowed_email('usuario@falsauni.pe'), 'falsauni.pe is rejected');
SELECT ok(NOT private.is_allowed_email('usuario@uni.pe.example.com'), 'uni.pe.example.com is rejected');
SELECT ok(NOT private.is_allowed_email('usuario@subdominio.uni.pe'), 'subdominio.uni.pe is rejected');
SELECT ok(NOT private.is_allowed_email('usuario@'), 'empty email domain is rejected');
SELECT ok(NOT private.is_allowed_email('usuario-sin-arroba'), 'email without at sign is rejected');

SET LOCAL ROLE anon;
SELECT pg_temp.set_request_context(NULL, 'anon');
SELECT ok(NOT pg_temp.try_sql('select * from public.profiles limit 1'), 'anon cannot query profiles');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000101', 'authenticated');
SELECT is((SELECT count(*)::integer FROM public.profiles), 1, 'authenticated user can query own profile');
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.profiles
		WHERE user_id = '00000000-0000-0000-0000-000000000107'
	),
	0,
	'authenticated user cannot query another profile'
);
SELECT ok(
	pg_temp.try_sql(
		format(
			'update public.profiles set display_name = %L where user_id = %L::uuid',
			'Nombre visible',
			'00000000-0000-0000-0000-000000000101'
		)
	),
	'authenticated user can update own display_name'
);

RESET ROLE;
SELECT is(
	(SELECT display_name FROM public.profiles WHERE user_id = '00000000-0000-0000-0000-000000000101'),
	'Nombre visible',
	'display_name update was persisted'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000101', 'authenticated');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'update public.profiles set email = %L where user_id = %L::uuid',
			'tampered@uni.pe',
			'00000000-0000-0000-0000-000000000101'
		)
	),
	'authenticated user cannot change email'
);

RESET ROLE;
SELECT is(
	(SELECT email FROM public.profiles WHERE user_id = '00000000-0000-0000-0000-000000000101'),
	'stage3a1-student@uni.pe',
	'email stays unchanged'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000101', 'authenticated');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'update public.profiles set account_status = %L::public.account_status where user_id = %L::uuid',
			'suspended',
			'00000000-0000-0000-0000-000000000101'
		)
	),
	'authenticated user cannot change account_status'
);

RESET ROLE;
SELECT is(
	(SELECT account_status::text FROM public.profiles WHERE user_id = '00000000-0000-0000-0000-000000000101'),
	'active',
	'account_status stays unchanged'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000101', 'authenticated');
SELECT is((SELECT count(*)::integer FROM public.user_roles), 1, 'user can query only active own roles');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'insert into public.user_roles (user_id, role, granted_by, granted_at) values (%L::uuid, %L::public.app_role, %L::uuid, now())',
			'00000000-0000-0000-0000-000000000101',
			'reviewer',
			'00000000-0000-0000-0000-000000000105'
		)
	),
	'user cannot insert directly into user_roles'
);
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'insert into public.role_audit_log (actor_user_id, target_user_id, action, role) values (%L::uuid, %L::uuid, %L, %L::public.app_role)',
			'00000000-0000-0000-0000-000000000101',
			'00000000-0000-0000-0000-000000000107',
			'grant',
			'reviewer'
		)
	),
	'user cannot insert directly into role_audit_log'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000102', 'authenticated');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'student',
			'contributor attempt'
		)
	),
	'contributor cannot grant roles'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000103', 'authenticated');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'student',
			'reviewer attempt'
		)
	),
	'reviewer cannot grant roles'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000104', 'authenticated');
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'administrator',
			'moderator administrator attempt'
		)
	),
	'moderator cannot grant administrator'
);
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'reviewer',
			'moderator reviewer attempt'
		)
	),
	'moderator cannot grant other roles'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000105', 'authenticated');
SELECT ok(
	pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'reviewer',
			'administrator grant'
		)
	),
	'administrator can grant a role to another user'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.user_roles
		WHERE user_id = '00000000-0000-0000-0000-000000000106'
			AND role = 'reviewer'
			AND revoked_at IS NULL
	),
	1,
	'administrator grant creates active assignment'
);
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000105',
			'reviewer',
			'self grant attempt'
		)
	),
	'administrator cannot self-assign roles through RPC'
);
SELECT ok(
	NOT pg_temp.try_sql(
		format(
			'select public.grant_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'reviewer',
			'duplicate grant attempt'
		)
	),
	'duplicate active role assignment is rejected'
);
SELECT ok(
	pg_temp.try_sql(
		format(
			'select public.revoke_user_role(%L::uuid, %L::public.app_role, %L)',
			'00000000-0000-0000-0000-000000000106',
			'reviewer',
			'administrator revoke'
		)
	),
	'administrator can revoke an active role'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.user_roles
		WHERE user_id = '00000000-0000-0000-0000-000000000106'
			AND role = 'reviewer'
			AND revoked_at IS NOT NULL
	),
	1,
	'revocation keeps historical assignment row'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.user_roles
		WHERE user_id = '00000000-0000-0000-0000-000000000106'
			AND role = 'reviewer'
			AND revoked_at IS NULL
	),
	0,
	'revoked role is no longer active'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.role_audit_log
		WHERE target_user_id = '00000000-0000-0000-0000-000000000106'
			AND action = 'grant'
			AND role = 'reviewer'
	),
	1,
	'grant writes audit entry'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.role_audit_log
		WHERE target_user_id = '00000000-0000-0000-0000-000000000106'
			AND action = 'revoke'
			AND role = 'reviewer'
	),
	1,
	'revoke writes audit entry'
);
SELECT ok(
	NOT pg_temp.try_sql($$update public.role_audit_log set metadata = '{"tampered": true}'::jsonb$$),
	'audit log cannot be updated directly'
);
SELECT ok(
	NOT pg_temp.try_sql('delete from public.role_audit_log'),
	'audit log cannot be deleted directly'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000102', 'authenticated');
SELECT ok(
	private.has_role('contributor'::public.app_role)
	AND NOT private.has_role('administrator'::public.app_role),
	'has_role reads auth.uid for contributor context'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000105', 'authenticated');
SELECT ok(private.has_role('administrator'::public.app_role), 'has_role reads auth.uid for administrator context');

RESET ROLE;
SELECT ok(
	(
		WITH expected(schema_name, function_name) AS (
			VALUES
				('private', 'normalize_allowed_email_domain'),
				('private', 'is_allowed_email'),
				('private', 'set_profile_defaults_and_validate'),
				('private', 'prevent_role_audit_log_mutation'),
				('private', 'has_role'),
				('private', 'has_any_role'),
				('private', 'can_manage_roles'),
				('public', 'grant_user_role'),
				('public', 'revoke_user_role')
		)
		SELECT count(*) = 9
			AND bool_and(pg_proc.prosecdef)
			AND bool_and(
				EXISTS (
					SELECT 1
					FROM unnest(pg_proc.proconfig) AS function_setting
					WHERE function_setting LIKE 'search_path=%'
				)
			)
		FROM expected
		INNER JOIN pg_namespace
			ON pg_namespace.nspname = expected.schema_name
		INNER JOIN pg_proc
			ON pg_proc.pronamespace = pg_namespace.oid
			AND pg_proc.proname = expected.function_name
	),
	'SECURITY DEFINER functions set explicit search_path'
);

SELECT * FROM finish();

ROLLBACK;
