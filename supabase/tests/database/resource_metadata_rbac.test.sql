SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT plan(105);

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
SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_enum
		WHERE enumtypid = 'public.resource_visibility'::regtype
			AND enumlabel = 'privileged'
	),
	'resource_visibility contains privileged'
);
SELECT ok(
	(
		SELECT count(*)::integer
		FROM pg_enum
		WHERE enumtypid = 'public.resource_rights_status'::regtype
			AND enumlabel IN ('open-license', 'public-domain')
	) = 2,
	'resource_rights_status contains open-license and public-domain'
);

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
	1,
	'suspended accounts retain exactly anonymous public resource access'
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
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			1024,
			NULL
		)
	$$,
	'contributor can reserve private PDF metadata through RPC'
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
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id = '10000000-0000-0000-0000-000000000010'
				LIMIT 1
			),
			'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			'ready for review'
		)
	$$,
	'contributor can atomically store and submit own resource'
);
SELECT is(
	(
		SELECT review_status::text
		FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000010'
	),
	'pending',
	'atomic finalization moves the resource to pending'
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
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			256,
			NULL
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
	'own-work'
);
SELECT public.register_resource_file_upload(
	'10000000-0000-0000-0000-000000000023',
	'pending-rights.pdf',
	'pdf'::public.resource_file_kind,
	'.pdf',
	'application/pdf',
	512,
	NULL
);
SELECT public.finalize_resource_file_upload(
	(
		SELECT id
		FROM public.resource_files
		WHERE resource_id = '10000000-0000-0000-0000-000000000023'
		LIMIT 1
	),
	'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
	'pending rights fixture'
);

-- Trusted fixture mutation: simulate rights becoming unresolved after storage
-- so the approval guard can be tested independently from upload finalization.
RESET ROLE;

UPDATE public.academic_resources
SET rights_status = 'pending'::public.resource_rights_status
WHERE id = '10000000-0000-0000-0000-000000000023';

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000504',
	'authenticated'
);

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
INSERT INTO public.external_identity_preauthorizations (
	normalized_email,
	authorized_by,
	reason
)
VALUES
	(
		'external-reader@example.com',
		'00000000-0000-0000-0000-000000000505',
		'resource matrix external reader'
	),
	(
		'external-privileged@example.com',
		'00000000-0000-0000-0000-000000000505',
		'resource matrix privileged external reader'
	);

INSERT INTO auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
VALUES
	(
		'00000000-0000-0000-0000-000000000508',
		'authenticated',
		'authenticated',
		'external-reader@example.com',
		now(),
		now(),
		now()
	),
	(
		'00000000-0000-0000-0000-000000000509',
		'authenticated',
		'authenticated',
		'external-privileged@example.com',
		now(),
		now(),
		now()
	),
	(
		'00000000-0000-0000-0000-000000000510',
		'authenticated',
		'authenticated',
		'stage4a-disabled@uni.pe',
		now(),
		now(),
		now()
	);

UPDATE public.profiles
SET account_status = 'disabled'::public.account_status
WHERE user_id = '00000000-0000-0000-0000-000000000510';

INSERT INTO public.user_entitlements (
	user_id,
	entitlement,
	granted_by,
	granted_at,
	reason
)
VALUES
	(
		'00000000-0000-0000-0000-000000000501',
		'privileged_material.read',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'institutional access matrix fixture'
	),
	(
		'00000000-0000-0000-0000-000000000509',
		'privileged_material.read',
		'00000000-0000-0000-0000-000000000505',
		now(),
		'external access matrix fixture'
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
		'10000000-0000-0000-0000-000000000030',
		'00000000-0000-0000-0000-000000000502',
		'course:matrix',
		'2026-1',
		'notes',
		'Matrix public resource',
		'Approved public access matrix fixture.',
		'public',
		'approved',
		'open-license',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000031',
		'00000000-0000-0000-0000-000000000502',
		'course:matrix',
		'2026-1',
		'exam',
		'Matrix restricted resource',
		'Approved restricted access matrix fixture.',
		'restricted',
		'approved',
		'own-work',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000032',
		'00000000-0000-0000-0000-000000000502',
		'course:matrix',
		'2026-1',
		'exam',
		'Matrix privileged resource',
		'Approved privileged access matrix fixture.',
		'privileged',
		'approved',
		'institutional',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000033',
		'00000000-0000-0000-0000-000000000502',
		'course:workflow',
		'2026-1',
		'notes',
		'Workflow draft resource',
		'Draft isolation fixture.',
		'private',
		'draft',
		'own-work',
		NULL,
		NULL,
		NULL
	),
	(
		'10000000-0000-0000-0000-000000000034',
		'00000000-0000-0000-0000-000000000502',
		'course:workflow',
		'2026-1',
		'notes',
		'Workflow pending resource',
		'Pending review fixture.',
		'private',
		'pending',
		'own-work',
		now(),
		NULL,
		NULL
	),
	(
		'10000000-0000-0000-0000-000000000035',
		'00000000-0000-0000-0000-000000000502',
		'course:workflow',
		'2026-1',
		'notes',
		'Workflow rejected resource',
		'Rejected isolation fixture.',
		'private',
		'rejected',
		'own-work',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
	),
	(
		'10000000-0000-0000-0000-000000000036',
		'00000000-0000-0000-0000-000000000502',
		'course:rights',
		'2026-1',
		'notes',
		'Public-domain public resource',
		'Public-domain structural fixture.',
		'public',
		'approved',
		'public-domain',
		now(),
		'00000000-0000-0000-0000-000000000504',
		now()
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
	review_status,
	rights_status,
	submitted_at,
	reviewed_by,
	reviewed_at
)
VALUES (
	'10000000-0000-0000-0000-000000000039',
	'00000000-0000-0000-0000-000000000502',
	'course:storage',
	'2026-1',
	'notes',
	'Failed storage public resource',
	'Public metadata whose private object failed to store.',
	'public',
	'approved',
	'open-license',
	now(),
	'00000000-0000-0000-0000-000000000504',
	now()
);

SELECT throws_ok(
	$$
		INSERT INTO public.academic_resources (
			id, owner_user_id, course_id, resource_type, title, description,
			visibility, review_status, rights_status, submitted_at, reviewed_by, reviewed_at
		) VALUES (
			'10000000-0000-0000-0000-000000000037',
			'00000000-0000-0000-0000-000000000502',
			'course:rights', 'notes', 'Invalid approved private',
			'Approved private must fail.', 'private', 'approved', 'own-work',
			now(), '00000000-0000-0000-0000-000000000504', now()
		)
	$$,
	'23514',
	'approved resources require a final audience',
	'approved plus private is structurally rejected'
);
SELECT throws_ok(
	$$
		INSERT INTO public.academic_resources (
			id, owner_user_id, course_id, resource_type, title, description,
			visibility, rights_status
		) VALUES (
			'10000000-0000-0000-0000-000000000038',
			'00000000-0000-0000-0000-000000000502',
			'course:rights', 'notes', 'Invalid institutional public',
			'Institutional public must fail.', 'public', 'institutional'
		)
	$$,
	'23514',
	'institutional rights do not allow public visibility',
	'institutional plus public is structurally rejected'
);
SELECT set_config('app.resource_review_transition', '', true);

INSERT INTO public.resource_files (
	id,
	resource_id,
	uploaded_by,
	display_filename,
	file_kind,
	normalized_extension,
	content_type,
	byte_size,
	sha256,
	storage_key_version
)
VALUES
	(
		'20000000-0000-0000-0000-000000000030',
		'10000000-0000-0000-0000-000000000030',
		'00000000-0000-0000-0000-000000000502',
		'Public matrix.pdf', 'pdf', '.pdf', 'application/pdf', 1030,
		'3030303030303030303030303030303030303030303030303030303030303030',
		'generic_v2'
	),
	(
		'20000000-0000-0000-0000-000000000031',
		'10000000-0000-0000-0000-000000000031',
		'00000000-0000-0000-0000-000000000502',
		'Restricted legacy.pdf', 'pdf', '.pdf', 'application/pdf', 1031,
		'3131313131313131313131313131313131313131313131313131313131313131',
		'legacy_pdf_v1'
	),
	(
		'20000000-0000-0000-0000-000000000032',
		'10000000-0000-0000-0000-000000000032',
		'00000000-0000-0000-0000-000000000502',
		'Privileged matrix.pdf', 'pdf', '.pdf', 'application/pdf', 1032,
		'3232323232323232323232323232323232323232323232323232323232323232',
		'generic_v2'
	),
	(
		'20000000-0000-0000-0000-000000000033',
		'10000000-0000-0000-0000-000000000033',
		'00000000-0000-0000-0000-000000000502',
		'Draft workflow.pdf', 'pdf', '.pdf', 'application/pdf', 1033,
		'3333333333333333333333333333333333333333333333333333333333333333',
		'generic_v2'
	),
	(
		'20000000-0000-0000-0000-000000000034',
		'10000000-0000-0000-0000-000000000034',
		'00000000-0000-0000-0000-000000000502',
		'Pending workflow.pdf', 'pdf', '.pdf', 'application/pdf', 1034,
		'3434343434343434343434343434343434343434343434343434343434343434',
		'legacy_pdf_v1'
	),
	(
		'20000000-0000-0000-0000-000000000035',
		'10000000-0000-0000-0000-000000000035',
		'00000000-0000-0000-0000-000000000502',
		'Rejected workflow.pdf', 'pdf', '.pdf', 'application/pdf', 1035,
		'3535353535353535353535353535353535353535353535353535353535353535',
		'generic_v2'
	),
	(
		'20000000-0000-0000-0000-000000000036',
		'10000000-0000-0000-0000-000000000036',
		'00000000-0000-0000-0000-000000000502',
		'Uploading public.pdf', 'pdf', '.pdf', 'application/pdf', 1036,
		'3636363636363636363636363636363636363636363636363636363636363636',
		'generic_v2'
	),
	(
		'20000000-0000-0000-0000-000000000039',
		'10000000-0000-0000-0000-000000000039',
		'00000000-0000-0000-0000-000000000502',
		'Failed public.pdf', 'pdf', '.pdf', 'application/pdf', 1039,
		'3939393939393939393939393939393939393939393939393939393939393939',
		'generic_v2'
	);

INSERT INTO private.resource_storage_objects (
	file_id,
	storage_key,
	storage_status,
	failure_reason,
	stored_at
)
VALUES
	(
		'20000000-0000-0000-0000-000000000030',
		'resources/10000000-0000-0000-0000-000000000030/20000000-0000-0000-0000-000000000030',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000031',
		'resources/10000000-0000-0000-0000-000000000031/20000000-0000-0000-0000-000000000031.pdf',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000032',
		'resources/10000000-0000-0000-0000-000000000032/20000000-0000-0000-0000-000000000032',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000033',
		'resources/10000000-0000-0000-0000-000000000033/20000000-0000-0000-0000-000000000033',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000034',
		'resources/10000000-0000-0000-0000-000000000034/20000000-0000-0000-0000-000000000034.pdf',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000035',
		'resources/10000000-0000-0000-0000-000000000035/20000000-0000-0000-0000-000000000035',
		'stored', NULL, now()
	),
	(
		'20000000-0000-0000-0000-000000000036',
		'resources/10000000-0000-0000-0000-000000000036/20000000-0000-0000-0000-000000000036',
		'uploading', NULL, NULL
	),
	(
		'20000000-0000-0000-0000-000000000039',
		'resources/10000000-0000-0000-0000-000000000039/20000000-0000-0000-0000-000000000039',
		'failed', 'fixture failure', NULL
	);


SELECT ok(
	EXISTS (
		SELECT 1 FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000030'
			AND rights_status = 'open-license'
			AND visibility = 'public'
			AND review_status = 'approved'
	),
	'open-license plus public is structurally allowed'
);
SELECT ok(
	EXISTS (
		SELECT 1 FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000036'
			AND rights_status = 'public-domain'
			AND visibility = 'public'
			AND review_status = 'approved'
	),
	'public-domain plus public is structurally allowed'
);

SET LOCAL ROLE anon;
SELECT pg_temp.set_request_context(NULL, 'anon');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	1,
	'anonymous sees only approved public resources'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000506', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	1,
	'suspended authenticated user sees exactly anonymous public access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000510', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	1,
	'disabled authenticated user sees exactly anonymous public access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000507', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	2,
	'active institutional user without role sees public and restricted only'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000501', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	3,
	'active institutional user with entitlement sees every approved audience'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000508', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	1,
	'active external user without entitlement sees public only'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000509', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	2,
	'active external user with entitlement sees public and privileged'
);
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id = '10000000-0000-0000-0000-000000000031'
	),
	0,
	'external entitlement does not grant restricted access'
);

RESET ROLE;
UPDATE public.user_entitlements
SET revoked_by = '00000000-0000-0000-0000-000000000505',
	revoked_at = now()
WHERE user_id = '00000000-0000-0000-0000-000000000509'
	AND entitlement = 'privileged_material.read'
	AND revoked_at IS NULL;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000509', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000030',
			'10000000-0000-0000-0000-000000000031',
			'10000000-0000-0000-0000-000000000032'
		)
	),
	1,
	'revoking entitlement removes privileged access immediately'
);

RESET ROLE;
INSERT INTO public.user_entitlements (user_id, entitlement, granted_by, granted_at, reason)
VALUES (
	'00000000-0000-0000-0000-000000000509',
	'privileged_material.read',
	'00000000-0000-0000-0000-000000000505',
	now(),
	'workflow entitlement-only fixture'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000503', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000032'),
	0,
	'reviewer without entitlement has no approved privileged role bypass'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000504', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000032'),
	1,
	'moderator can inspect approved privileged resources editorially'
);
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000034'),
	1,
	'moderator can inspect pending resources'
);
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000033'),
	0,
	'moderator cannot inspect another owner draft solely by role'
);
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000035'),
	0,
	'moderator cannot inspect another owner rejected resource solely by role'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000505', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000032'),
	1,
	'administrator can inspect approved privileged resources administratively'
);
SELECT is(
	(
		SELECT count(*)::integer FROM public.academic_resources
		WHERE id IN (
			'10000000-0000-0000-0000-000000000033',
			'10000000-0000-0000-0000-000000000034',
			'10000000-0000-0000-0000-000000000035'
		)
	),
	3,
	'administrator retains draft pending and rejected workflow access'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000502', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000032'),
	0,
	'owner without entitlement has no approved privileged ownership bypass'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000503', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000034'),
	1,
	'reviewer can inspect pending resources'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000509', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.academic_resources WHERE id = '10000000-0000-0000-0000-000000000034'),
	0,
	'entitlement-only external user cannot inspect pending resources'
);


RESET ROLE;
SELECT ok(
	to_regprocedure('public.get_resource_file_read_descriptor(uuid,uuid)') IS NOT NULL
	AND (
		SELECT proargnames[1:2] = ARRAY['resource_id', 'file_id']
		FROM pg_proc
		WHERE oid = 'public.get_resource_file_read_descriptor(uuid,uuid)'::regprocedure
	),
	'resource file read descriptor RPC exists with exact domain-id arguments'
);
SELECT ok(
	ARRAY(
		SELECT attribute.attname::text
		FROM pg_attribute AS attribute
		WHERE attribute.attrelid = 'public.resource_file_read_descriptor'::regclass
			AND attribute.attnum > 0
			AND NOT attribute.attisdropped
		ORDER BY attribute.attnum
	) = ARRAY[
		'resource_id', 'file_id', 'display_filename', 'file_kind',
		'normalized_extension', 'content_type', 'byte_size', 'sha256',
		'storage_key_version'
	],
	'read descriptor exposes exactly the safe metadata columns'
);
SELECT ok(
	NOT EXISTS (
		SELECT 1
		FROM pg_attribute AS attribute
		WHERE attribute.attrelid = 'public.resource_file_read_descriptor'::regclass
			AND attribute.attname IN ('storage_key', 'storage_status', 'uploaded_by')
			AND attribute.attnum > 0
			AND NOT attribute.attisdropped
	),
	'read descriptor excludes private storage and uploader details'
);
SELECT ok(
	(
		SELECT pg_proc.prosecdef
			AND EXISTS (
				SELECT 1
				FROM unnest(COALESCE(pg_proc.proconfig, ARRAY[]::text[])) AS setting(value)
				WHERE replace(setting.value, 'search_path=', '') IN ('', '""')
			)
		FROM pg_proc
		WHERE oid = 'public.get_resource_file_read_descriptor(uuid,uuid)'::regprocedure
	),
	'read descriptor is SECURITY DEFINER with empty search_path'
);
SELECT ok(
	has_function_privilege('anon', 'public.get_resource_file_read_descriptor(uuid,uuid)', 'EXECUTE'),
	'anon can execute the read descriptor RPC'
);
SELECT ok(
	has_function_privilege('authenticated', 'public.get_resource_file_read_descriptor(uuid,uuid)', 'EXECUTE'),
	'authenticated can execute the read descriptor RPC'
);
SELECT ok(
	NOT EXISTS (
		SELECT 1
		FROM pg_proc
		CROSS JOIN LATERAL aclexplode(
			COALESCE(pg_proc.proacl, acldefault('f', pg_proc.proowner))
		) AS privilege
		WHERE pg_proc.oid = 'public.get_resource_file_read_descriptor(uuid,uuid)'::regprocedure
			AND privilege.grantee = 0
			AND privilege.privilege_type = 'EXECUTE'
	),
	'PUBLIC cannot execute the read descriptor RPC'
);

SET LOCAL ROLE anon;
SELECT pg_temp.set_request_context(NULL, 'anon');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000030',
		'20000000-0000-0000-0000-000000000030'
	)),
	1,
	'RA-01 anon receives a stored approved public generic_v2 descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000031',
		'20000000-0000-0000-0000-000000000031'
	)),
	0,
	'RA-03 anon cannot receive a restricted descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'90000000-0000-0000-0000-000000000000',
		'90000000-0000-0000-0000-000000000001'
	)),
	0,
	'RA-11 a missing pair returns no descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000030',
		'20000000-0000-0000-0000-000000000031'
	)),
	0,
	'RA-11 a wrong resource id with a real file id returns no descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000036',
		'20000000-0000-0000-0000-000000000036'
	)),
	0,
	'an uploading private object returns no descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000039',
		'20000000-0000-0000-0000-000000000039'
	)),
	0,
	'a failed private object returns no descriptor'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000507', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000031',
		'20000000-0000-0000-0000-000000000031'
	)),
	1,
	'RA-03 active institutional identity receives restricted legacy descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000032',
		'20000000-0000-0000-0000-000000000032'
	)),
	0,
	'RA-04 privileged descriptor is hidden without entitlement'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000501', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000032',
		'20000000-0000-0000-0000-000000000032'
	)),
	1,
	'RA-04 institutional entitlement holder receives privileged descriptor'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000509', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000032',
		'20000000-0000-0000-0000-000000000032'
	)),
	1,
	'RA-04 external entitlement holder receives privileged descriptor'
);
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor(
		'10000000-0000-0000-0000-000000000031',
		'20000000-0000-0000-0000-000000000031'
	)),
	0,
	'RA-05 external entitlement holder still cannot receive restricted descriptor'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000506', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000030',
				'20000000-0000-0000-0000-000000000030'
			)
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000031',
				'20000000-0000-0000-0000-000000000031'
			)
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000032',
				'20000000-0000-0000-0000-000000000032'
			)
		) AS descriptors
	),
	1,
	'RA-02 suspended identity receives public descriptor only'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000510', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000030',
				'20000000-0000-0000-0000-000000000030'
			)
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000031',
				'20000000-0000-0000-0000-000000000031'
			)
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor(
				'10000000-0000-0000-0000-000000000032',
				'20000000-0000-0000-0000-000000000032'
			)
		) AS descriptors
	),
	1,
	'RA-02 disabled identity receives public descriptor only'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000502', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000033', '20000000-0000-0000-0000-000000000033')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000034', '20000000-0000-0000-0000-000000000034')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000035', '20000000-0000-0000-0000-000000000035')
		) AS descriptors
	),
	3,
	'RA-06 owner receives draft pending and rejected workflow descriptors'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000503', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000034', '20000000-0000-0000-0000-000000000034')),
	1,
	'reviewer receives pending workflow descriptor'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000033', '20000000-0000-0000-0000-000000000033')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000035', '20000000-0000-0000-0000-000000000035')
		) AS descriptors
	),
	0,
	'reviewer cannot receive another owner draft or rejected descriptor'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000504', 'authenticated');
SELECT is(
	(SELECT count(*)::integer FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000034', '20000000-0000-0000-0000-000000000034')),
	1,
	'moderator receives pending workflow descriptor'
);
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000033', '20000000-0000-0000-0000-000000000033')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000035', '20000000-0000-0000-0000-000000000035')
		) AS descriptors
	),
	0,
	'RA-07 moderator cannot receive another owner draft or rejected descriptor'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context('00000000-0000-0000-0000-000000000505', 'authenticated');
SELECT is(
	(
		SELECT count(*)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000033', '20000000-0000-0000-0000-000000000033')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000034', '20000000-0000-0000-0000-000000000034')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000035', '20000000-0000-0000-0000-000000000035')
		) AS descriptors
	),
	3,
	'RA-08 administrator receives draft pending and rejected descriptors'
);
SELECT is(
	(
		SELECT count(DISTINCT descriptor.storage_key_version)::integer
		FROM (
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000030', '20000000-0000-0000-0000-000000000030')
			UNION ALL
			SELECT * FROM public.get_resource_file_read_descriptor('10000000-0000-0000-0000-000000000031', '20000000-0000-0000-0000-000000000031')
		) AS descriptor
	),
	2,
	'RF-18 authorized stored descriptors preserve legacy_pdf_v1 and generic_v2 layouts'
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
