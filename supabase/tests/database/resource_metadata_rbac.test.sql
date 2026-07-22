SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT no_plan();

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

CREATE TEMP TABLE resource_test_users (
	kind text PRIMARY KEY,
	id uuid NOT NULL,
	email text NOT NULL
);

INSERT INTO resource_test_users (kind, id, email)
VALUES
	('student', '00000000-0000-0000-0000-000000000501', 'stage4a-student@uni.pe'),
	('contributor', '00000000-0000-0000-0000-000000000502', 'stage4a-contributor@uni.pe'),
	('reviewer', '00000000-0000-0000-0000-000000000503', 'stage4a-reviewer@uni.pe'),
	('moderator', '00000000-0000-0000-0000-000000000504', 'stage4a-moderator@uni.pe'),
	('administrator', '00000000-0000-0000-0000-000000000505', 'stage4a-admin@uni.pe'),
	('suspended', '00000000-0000-0000-0000-000000000506', 'stage4a-suspended@uni.pe'),
	('active_no_role', '00000000-0000-0000-0000-000000000507', 'stage4a-active-no-role@uni.pe');

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
SELECT id, 'authenticated', 'authenticated', email, now(), now(), now()
FROM resource_test_users;

UPDATE public.profiles
SET display_name = resource_test_users.kind
FROM resource_test_users
WHERE public.profiles.user_id = resource_test_users.id;

UPDATE public.profiles
SET account_status = 'suspended'::public.account_status
WHERE user_id = '00000000-0000-0000-0000-000000000506';

INSERT INTO public.user_roles (user_id, role, granted_by, granted_at, reason)
VALUES
	(
		'00000000-0000-0000-0000-000000000505',
		'administrator',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test administrator bootstrap'
	),
	(
		'00000000-0000-0000-0000-000000000501',
		'student',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test student role'
	),
	(
		'00000000-0000-0000-0000-000000000502',
		'contributor',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test contributor role'
	),
	(
		'00000000-0000-0000-0000-000000000503',
		'reviewer',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test reviewer role'
	),
	(
		'00000000-0000-0000-0000-000000000504',
		'moderator',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test moderator role'
	),
	(
		'00000000-0000-0000-0000-000000000506',
		'student',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'test suspended role'
	);

SELECT ok(to_regclass('public.academic_resources') IS NOT NULL, 'academic_resources exists');
SELECT ok(to_regclass('public.resource_files') IS NOT NULL, 'resource_files exists');
SELECT ok(to_regclass('private.resource_storage_objects') IS NOT NULL, 'private resource_storage_objects exists');
SELECT ok(to_regclass('public.resource_review_events') IS NOT NULL, 'resource_review_events exists');

SELECT ok(to_regtype('public.resource_review_status') IS NOT NULL, 'resource_review_status enum exists');
SELECT ok(to_regtype('public.resource_storage_status') IS NOT NULL, 'resource_storage_status enum exists');
SELECT ok(to_regtype('public.resource_visibility') IS NOT NULL, 'resource_visibility enum exists');
SELECT ok(to_regtype('public.resource_rights_status') IS NOT NULL, 'resource_rights_status enum exists');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.academic_resources'::regclass), 'academic_resources has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.resource_files'::regclass), 'resource_files has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'private.resource_storage_objects'::regclass), 'resource_storage_objects has RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.resource_review_events'::regclass), 'resource_review_events has RLS enabled');

SELECT ok(
	NOT EXISTS (
		SELECT 1
		FROM information_schema.columns
		WHERE table_schema = 'public'
			AND table_name = 'resource_files'
			AND column_name = 'storage_key'
	),
	'public resource_files never exposes storage_key column'
);

SELECT ok(
	NOT EXISTS (
		SELECT 1
		FROM information_schema.table_privileges
		WHERE table_schema = 'private'
			AND table_name = 'resource_storage_objects'
			AND grantee IN ('anon', 'authenticated')
	),
	'anon and authenticated have no direct privileges on private resource storage objects'
);

SELECT set_config('app.resource_review_transition', 'on', true);

INSERT INTO public.academic_resources (
	id,
	owner_user_id,
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	visibility,
	review_status,
	rights_status,
	submitted_at,
	reviewed_by,
	reviewed_at
)
VALUES
	(
		'10000000-0000-0000-0000-000000000001',
		'00000000-0000-0000-0000-000000000502',
		'course:bma01',
		'2026-1',
		'notes',
		'Approved public notes',
		'Approved public metadata without files.',
		'public',
		'approved',
		'bibliographic-reference-only',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000002',
		'00000000-0000-0000-0000-000000000502',
		'course:bma01',
		'2026-1',
		'exam',
		'Approved restricted exam',
		'Approved restricted metadata without files.',
		'restricted',
		'approved',
		'own-work',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000003',
		'00000000-0000-0000-0000-000000000502',
		'course:bma01',
		'2026-1',
		'exam',
		'Pending exam',
		'Pending resource under review.',
		'restricted',
		'pending',
		'own-work',
		now(),
		NULL,
		NULL
	);

SELECT set_config('app.resource_review_transition', '', true);

RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.set_request_context(NULL, 'anon');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources),
	1,
	'anon reads only approved public resources'
);
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE visibility = 'restricted'),
	0,
	'anon cannot read approved restricted resources'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000507', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources),
	2,
	'active authenticated user reads approved public and restricted resources without automatic role assignment'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000506', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources),
	0,
	'suspended accounts lose authenticated resource access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000502', 'authenticated');
SELECT lives_ok(
	$$
		INSERT INTO public.academic_resources (
			id,
			owner_user_id,
			course_id,
			academic_term_id,
			resource_type,
			title,
			description,
			visibility,
			rights_status
		)
		VALUES (
			'10000000-0000-0000-0000-000000000010',
			'00000000-0000-0000-0000-000000000502',
			'course:bma01',
			'2026-1',
			'exam',
			'Contributor draft',
			'Contributor draft metadata.',
			'restricted',
			'own-work'
		)
	$$,
	'contributor can create own draft resource'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		INSERT INTO public.academic_resources (
			id,
			owner_user_id,
			course_id,
			resource_type,
			title,
			description,
			review_status
		)
		VALUES (
			'10000000-0000-0000-0000-000000000011',
			'00000000-0000-0000-0000-000000000503',
			'course:bma01',
			'exam',
			'Wrong owner',
			'Wrong owner draft.',
			'draft'
		)
	$$),
	'contributor cannot create resources for another owner'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		INSERT INTO public.academic_resources (
			id,
			owner_user_id,
			course_id,
			resource_type,
			title,
			description,
			review_status
		)
		VALUES (
			'10000000-0000-0000-0000-000000000012',
			'00000000-0000-0000-0000-000000000502',
			'course:bma01',
			'exam',
			'Approved direct insert',
			'Invalid approved direct insert.',
			'approved'
		)
	$$),
	'contributor cannot create an already approved resource'
);
SELECT ok(
	pg_temp.try_sql($$
		UPDATE public.academic_resources
		SET title = 'Contributor draft edited'
		WHERE id = '10000000-0000-0000-0000-000000000010'
	$$),
	'contributor can edit own draft metadata'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		UPDATE public.academic_resources
		SET review_status = 'approved'
		WHERE id = '10000000-0000-0000-0000-000000000010'
	$$),
	'direct review status changes are blocked'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		INSERT INTO public.resource_files (
			resource_id,
			uploaded_by,
			display_filename,
			content_type,
			byte_size
		)
		VALUES (
			'10000000-0000-0000-0000-000000000010',
			'00000000-0000-0000-0000-000000000502',
			'direct.pdf',
			'application/pdf',
			128
		)
	$$),
	'file metadata cannot be inserted directly; RPC must be used'
);
SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'10000000-0000-0000-0000-000000000010',
			'exam.pdf',
			'application/pdf',
			1024,
			'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			'resources/10000000-0000-0000-0000-000000000010/exam.pdf'
		)
	$$,
	'contributor can register private file metadata through RPC'
);
SELECT is(
	(SELECT count(*)::integer FROM public.resource_files WHERE resource_id = '10000000-0000-0000-0000-000000000010'),
	1,
	'file metadata row is visible to owner after registration'
);
SELECT ok(
	NOT pg_temp.try_sql('SELECT storage_key FROM private.resource_storage_objects LIMIT 1'),
	'authenticated users cannot select private storage keys'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		UPDATE private.resource_storage_objects
		SET storage_status = 'stored'
	$$),
	'storage status cannot be changed directly'
);
SELECT lives_ok(
	$$
		SELECT public.mark_resource_file_stored(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id = '10000000-0000-0000-0000-000000000010'
				LIMIT 1
			),
			'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
		)
	$$,
	'contributor can mark own uploading file as stored through RPC'
);
SELECT lives_ok(
	$$ SELECT public.submit_academic_resource('10000000-0000-0000-0000-000000000010', 'ready for review') $$,
	'contributor can submit own stored resource for review'
);
SELECT ok(
	pg_temp.try_sql($$
		UPDATE public.academic_resources
		SET title = 'Pending direct edit'
		WHERE id = '10000000-0000-0000-0000-000000000010'
	$$),
	'direct pending edit statement is safely filtered by RLS'
);
SELECT is(
	(
		SELECT title
		FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000010'
	),
	'Contributor draft edited',
	'owner cannot edit pending resources directly'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.reject_academic_resource('10000000-0000-0000-0000-000000000010', 'contributor attempt')
	$$),
	'contributor cannot reject resources'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000010', 'contributor attempt')
	$$),
	'contributor cannot approve resources'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000503', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.academic_resources
		WHERE review_status = 'pending'
	),
	2,
	'reviewer can read pending resources under review'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000010', 'reviewer attempt')
	$$),
	'reviewer cannot approve or publish resources'
);
SELECT lives_ok(
	$$ SELECT public.reject_academic_resource('10000000-0000-0000-0000-000000000010', 'needs changes') $$,
	'reviewer can reject pending resources'
);
RESET ROLE;
SELECT is(
	(
		SELECT review_status::text
		FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000010'
	),
	'rejected',
	'reviewer rejection moves resource to rejected'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000502', 'authenticated');
SELECT ok(
	pg_temp.try_sql($$
		UPDATE public.academic_resources
		SET title = 'Contributor rejected edit'
		WHERE id = '10000000-0000-0000-0000-000000000010'
	$$),
	'owner can edit rejected resources'
);

INSERT INTO public.academic_resources (
	id,
	owner_user_id,
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	visibility,
	rights_status
)
VALUES (
	'10000000-0000-0000-0000-000000000020',
	'00000000-0000-0000-0000-000000000502',
	'course:bma01',
	'2026-1',
	'book-reference',
	'Bibliographic metadata only',
	'Bibliographic reference without stored file.',
	'public',
	'bibliographic-reference-only'
);
SELECT lives_ok(
	$$ SELECT public.submit_academic_resource('10000000-0000-0000-0000-000000000020', 'metadata only') $$,
	'bibliographic-reference-only metadata can be submitted without files'
);

INSERT INTO public.academic_resources (
	id,
	owner_user_id,
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	visibility,
	rights_status
)
VALUES (
	'10000000-0000-0000-0000-000000000021',
	'00000000-0000-0000-0000-000000000502',
	'course:bma01',
	'2026-1',
	'book-reference',
	'Bibliographic with attempted file',
	'Bibliographic reference must not store files.',
	'restricted',
	'bibliographic-reference-only'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'10000000-0000-0000-0000-000000000021',
			'reference.pdf',
			'application/pdf',
			256,
			NULL,
			'resources/10000000-0000-0000-0000-000000000021/reference.pdf'
		)
	$$),
	'bibliographic-reference-only resources cannot register stored files'
);

INSERT INTO public.academic_resources (
	id,
	owner_user_id,
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	visibility,
	rights_status
)
VALUES (
	'10000000-0000-0000-0000-000000000022',
	'00000000-0000-0000-0000-000000000502',
	'course:bma01',
	'2026-1',
	'notes',
	'Copyright restricted metadata',
	'Copyright restricted resource.',
	'restricted',
	'copyright-restricted'
);
SELECT lives_ok(
	$$ SELECT public.submit_academic_resource('10000000-0000-0000-0000-000000000022', 'rights problem') $$,
	'copyright-restricted metadata can be submitted for rejection or administrative review'
);

INSERT INTO public.academic_resources (
	id,
	owner_user_id,
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	visibility,
	rights_status
)
VALUES (
	'10000000-0000-0000-0000-000000000023',
	'00000000-0000-0000-0000-000000000502',
	'course:bma01',
	'2026-1',
	'notes',
	'Pending rights with file',
	'Pending rights must block approval when a file exists.',
	'restricted',
	'pending'
);
SELECT public.register_resource_file_upload(
	'10000000-0000-0000-0000-000000000023',
	'pending-rights.pdf',
	'application/pdf',
	512,
	NULL,
	'resources/10000000-0000-0000-0000-000000000023/pending-rights.pdf'
);
SELECT public.mark_resource_file_stored(
	(
		SELECT id
		FROM public.resource_files
		WHERE resource_id = '10000000-0000-0000-0000-000000000023'
		LIMIT 1
	),
	NULL
);
SELECT public.submit_academic_resource('10000000-0000-0000-0000-000000000023', 'pending rights');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000504', 'authenticated');
SELECT lives_ok(
	$$ SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000020', 'bibliographic metadata approved') $$,
	'moderator can approve bibliographic-reference-only metadata without files'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000022', 'copyright attempt')
	$$),
	'copyright-restricted resources cannot be approved'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000023', 'pending rights attempt')
	$$),
	'pending rights block approval when files are stored'
);
SELECT lives_ok(
	$$ SELECT public.approve_academic_resource('10000000-0000-0000-0000-000000000003', 'moderator approval') $$,
	'moderator can approve pending resources'
);
SELECT is(
	(
		SELECT review_status::text
		FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000003'
	),
	'approved',
	'moderator approval publishes the resource'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000505', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources),
	8,
	'administrator can read all academic resources'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE action IN ('submit', 'approve', 'reject', 'storage_stored')
	),
	9,
	'review and storage RPCs write audit events'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		INSERT INTO public.resource_review_events (
			resource_id,
			actor_user_id,
			to_status,
			action
		)
		VALUES (
			'10000000-0000-0000-0000-000000000003',
			'00000000-0000-0000-0000-000000000505',
			'approved',
			'approve'
		)
	$$),
	'clients cannot insert review events directly'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		UPDATE public.resource_review_events
		SET metadata = '{"tampered": true}'::jsonb
	$$),
	'resource review events cannot be updated'
);
SELECT ok(
	NOT pg_temp.try_sql('DELETE FROM public.resource_review_events'),
	'resource review events cannot be deleted'
);

RESET ROLE;
SELECT ok(
	(
		WITH expected(schema_name, function_name) AS (
			VALUES
				('private', 'is_active_user'),
				('private', 'can_create_academic_resource'),
				('private', 'can_edit_academic_resource'),
				('private', 'can_review_resource'),
				('private', 'can_publish_resource'),
				('private', 'can_read_academic_resource'),
				('private', 'can_read_resource_by_id'),
				('private', 'resource_has_stored_files'),
				('private', 'resource_has_unstored_files'),
				('private', 'resource_rights_allow_stored_files'),
				('private', 'resource_rights_block_approval'),
				('private', 'can_register_resource_file'),
				('private', 'set_academic_resource_defaults_and_validate'),
				('private', 'set_resource_file_defaults_and_validate'),
				('private', 'set_resource_storage_object_defaults_and_validate'),
				('private', 'prevent_resource_review_event_mutation'),
				('public', 'submit_academic_resource'),
				('public', 'reject_academic_resource'),
				('public', 'approve_academic_resource'),
				('public', 'register_resource_file_upload'),
				('public', 'mark_resource_file_stored'),
				('public', 'mark_resource_file_failed')
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
				ON pg_namespace.nspname = expected.schema_name
			INNER JOIN pg_proc
				ON pg_proc.pronamespace = pg_namespace.oid
				AND pg_proc.proname = expected.function_name
		)
		SELECT count(*) = 22
			AND bool_and(prosecdef)
			AND bool_and(has_empty_search_path)
		FROM function_settings
	),
	'4A SECURITY DEFINER functions set empty search_path'
);

SELECT * FROM finish();

ROLLBACK;
