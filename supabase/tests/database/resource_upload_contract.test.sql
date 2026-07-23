SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT no_plan();

SELECT ok(
	to_regprocedure(
		'public.register_resource_file_upload(uuid,text,text,bigint,text)'
	) IS NOT NULL,
	'five-argument upload reservation RPC exists'
);

SELECT ok(
	to_regprocedure(
		'public.register_resource_file_upload(uuid,text,text,bigint,text,text)'
	) IS NULL,
	'legacy client-supplied storage key RPC no longer exists'
);

SELECT ok(
	has_function_privilege(
		'authenticated',
		'public.register_resource_file_upload(uuid,text,text,bigint,text)',
		'EXECUTE'
	),
	'authenticated can reserve an upload'
);

SELECT ok(
	has_function_privilege(
		'authenticated',
		'public.finalize_resource_file_upload(uuid,text,text)',
		'EXECUTE'
	),
	'authenticated can finalize an upload'
);

SELECT ok(
	has_function_privilege(
		'authenticated',
		'public.abort_resource_file_upload(uuid,text)',
		'EXECUTE'
	),
	'authenticated can abort an upload reservation'
);

SELECT ok(
	has_function_privilege(
		'authenticated',
		'public.mark_resource_file_failed(uuid,text)',
		'EXECUTE'
	),
	'authenticated can preserve failed storage metadata for reconciliation'
);

SELECT ok(
	NOT has_function_privilege(
		'authenticated',
		'public.mark_resource_file_stored(uuid,text)',
		'EXECUTE'
	),
	'authenticated cannot bypass atomic finalization'
);

SELECT ok(
	NOT has_function_privilege(
		'anon',
		'public.register_resource_file_upload(uuid,text,text,bigint,text)',
		'EXECUTE'
	)
	AND NOT has_function_privilege(
		'anon',
		'public.finalize_resource_file_upload(uuid,text,text)',
		'EXECUTE'
	)
	AND NOT has_function_privilege(
		'anon',
		'public.abort_resource_file_upload(uuid,text)',
		'EXECUTE'
	)
	AND NOT has_function_privilege(
		'anon',
		'public.mark_resource_file_failed(uuid,text)',
		'EXECUTE'
	),
	'anon cannot execute upload lifecycle RPCs'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname = 'resource_files_one_file_per_resource_key'
	),
	'one file per resource constraint exists'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname = 'resource_files_byte_size_max_check'
	),
	'10 MB database size constraint exists'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname = 'resource_files_content_type_pdf_check'
	),
	'PDF content type constraint exists'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname = 'resource_files_display_filename_pdf_check'
	),
	'PDF filename constraint exists'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_review_events'::regclass
			AND conname = 'resource_review_events_action_check'
			AND pg_get_constraintdef(oid) LIKE '%storage_aborted%'
	),
	'storage_aborted is an allowed audit action'
);

SELECT ok(
	(
		SELECT count(*) = 3
			AND bool_and(pg_proc.prosecdef)
			AND bool_and(
				EXISTS (
					SELECT 1
					FROM unnest(
						COALESCE(pg_proc.proconfig, ARRAY[]::text[])
					) AS function_setting(setting)
					WHERE replace(function_setting.setting, 'search_path=', '')
						IN ('', '""')
				)
			)
		FROM pg_proc
		INNER JOIN pg_namespace
			ON pg_namespace.oid = pg_proc.pronamespace
		WHERE pg_namespace.nspname = 'public'
			AND pg_proc.proname IN (
				'register_resource_file_upload',
				'finalize_resource_file_upload',
				'abort_resource_file_upload'
			)
	),
	'4B.2 RPCs are SECURITY DEFINER with empty search_path'
);

-- Behavioral contract fixtures and helpers.

CREATE OR REPLACE FUNCTION pg_temp.set_request_context(
	user_id uuid,
	jwt_role text
)
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
	PERFORM set_config(
		'request.jwt.claim.sub',
		COALESCE(user_id::text, ''),
		true
	);
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

CREATE TEMP TABLE upload_contract_users (
	kind text PRIMARY KEY,
	id uuid NOT NULL,
	email text NOT NULL
);

INSERT INTO upload_contract_users (kind, id, email)
VALUES
	(
		'administrator',
		'00000000-0000-0000-0000-000000000801',
		'stage4b-admin@uni.pe'
	),
	(
		'contributor',
		'00000000-0000-0000-0000-000000000802',
		'stage4b-contributor@uni.pe'
	),
	(
		'other_contributor',
		'00000000-0000-0000-0000-000000000803',
		'stage4b-other-contributor@uni.pe'
	),
	(
		'student',
		'00000000-0000-0000-0000-000000000804',
		'stage4b-student@uni.pe'
	);

INSERT INTO auth.users (
	id,
	aud,
	role,
	email,
	email_confirmed_at,
	created_at,
	updated_at
)
SELECT
	id,
	'authenticated',
	'authenticated',
	email,
	now(),
	now(),
	now()
FROM upload_contract_users;

UPDATE public.profiles
SET display_name = upload_contract_users.kind
FROM upload_contract_users
WHERE public.profiles.user_id = upload_contract_users.id;

INSERT INTO public.user_roles (
	user_id,
	role,
	granted_by,
	granted_at,
	reason
)
VALUES
	(
		'00000000-0000-0000-0000-000000000801',
		'administrator',
		'00000000-0000-0000-0000-000000000801',
		now(),
		'4B.2 test administrator'
	),
	(
		'00000000-0000-0000-0000-000000000802',
		'contributor',
		'00000000-0000-0000-0000-000000000801',
		now(),
		'4B.2 test contributor'
	),
	(
		'00000000-0000-0000-0000-000000000803',
		'contributor',
		'00000000-0000-0000-0000-000000000801',
		now(),
		'4B.2 other contributor'
	),
	(
		'00000000-0000-0000-0000-000000000804',
		'student',
		'00000000-0000-0000-0000-000000000801',
		now(),
		'4B.2 test student'
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
VALUES
	(
		'20000000-0000-0000-0000-000000000001',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Boundary size upload',
		'Accept exactly ten million bytes.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000002',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Oversized upload',
		'Reject a file above ten million bytes.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000003',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Atomic finalization',
		'Exercise atomic storage finalization.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000004',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'notes',
		'Hash mismatch rollback',
		'Exercise rollback on a conflicting reserved hash.',
		'restricted',
		'own-work'
	);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000001',
			'boundary.pdf',
			'application/pdf',
			10000000,
			NULL
		)
	$$,
	'exactly 10000000 bytes is accepted'
);

RESET ROLE;

SELECT is(
	(
		SELECT byte_size
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000001'
	),
	10000000::bigint,
	'boundary file size is stored exactly'
);

SELECT ok(
	(
		SELECT storage_object.storage_key =
			'resources/'
			|| resource_file.resource_id::text
			|| '/'
			|| resource_file.id::text
			|| '.pdf'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id =
			'20000000-0000-0000-0000-000000000001'
	),
	'storage key is derived from trusted resource and file identifiers'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000001',
			'second.pdf',
			'application/pdf',
			512,
			NULL
		)
	$$),
	'a resource cannot reserve a second file'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000002',
			'oversized.pdf',
			'application/pdf',
			10000001,
			NULL
		)
	$$),
	'10000001 bytes is rejected'
);

RESET ROLE;

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000002'
	),
	0,
	'oversized reservation leaves no file metadata'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000003',
			'atomic.pdf',
			'application/pdf',
			2048,
			NULL
		)
	$$,
	'valid upload reservation succeeds'
);

SELECT lives_ok(
	$$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id =
					'20000000-0000-0000-0000-000000000003'
			),
			'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			'atomic finalization'
		)
	$$,
	'valid finalization succeeds atomically'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			resource_file.sha256 =
				'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
			AND storage_object.storage_status =
				'stored'::public.resource_storage_status
			AND storage_object.stored_at IS NOT NULL
			AND academic_resource.review_status =
				'pending'::public.resource_review_status
			AND academic_resource.submitted_at IS NOT NULL
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.resource_id =
			'20000000-0000-0000-0000-000000000003'
	),
	'finalization updates file, storage and resource together'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000003'
			AND action IN ('storage_stored', 'submit')
	),
	2,
	'finalization writes exactly two audit events'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id =
					'20000000-0000-0000-0000-000000000003'
			),
			'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			'ignored idempotent retry'
		)
	$$,
	'finalization retry with the same hash is idempotent'
);

RESET ROLE;

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000003'
			AND action IN ('storage_stored', 'submit')
	),
	2,
	'idempotent retry does not duplicate audit events'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id =
					'20000000-0000-0000-0000-000000000003'
			),
			'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			'conflicting retry'
		)
	$$),
	'finalization retry with a different hash is rejected'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			resource_file.sha256 =
				'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
			AND storage_object.storage_status =
				'stored'::public.resource_storage_status
			AND academic_resource.review_status =
				'pending'::public.resource_review_status
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.resource_id =
			'20000000-0000-0000-0000-000000000003'
	),
	'conflicting retry preserves the completed state'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000004',
			'reserved-hash.pdf',
			'application/pdf',
			4096,
			'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
		)
	$$,
	'reservation can record an expected hash'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id
				FROM public.resource_files
				WHERE resource_id =
					'20000000-0000-0000-0000-000000000004'
			),
			'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
			'conflicting reserved hash'
		)
	$$),
	'finalization rejects a hash that conflicts with the reservation'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			resource_file.sha256 =
				'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
			AND storage_object.storage_status =
				'uploading'::public.resource_storage_status
			AND storage_object.stored_at IS NULL
			AND academic_resource.review_status =
				'draft'::public.resource_review_status
			AND academic_resource.submitted_at IS NULL
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.resource_id =
			'20000000-0000-0000-0000-000000000004'
	),
	'failed finalization rolls back every protected state'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000004'
	),
	0,
	'failed finalization writes no audit events'
);

-- Abort, compensation and authorization behavior.

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
VALUES
	(
		'20000000-0000-0000-0000-000000000005',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Abort uploading reservation',
		'Exercise abort from uploading.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000006',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Failed storage compensation',
		'Preserve failed storage before cleanup.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000007',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'exam',
		'Stored abort rejection',
		'Stored files must not be aborted.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000008',
		'00000000-0000-0000-0000-000000000802',
		'course:bma01',
		'2026-1',
		'notes',
		'Wrong owner reservation',
		'Another contributor must not reserve this resource.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000009',
		'00000000-0000-0000-0000-000000000804',
		'course:bma01',
		'2026-1',
		'notes',
		'Student-owned resource',
		'A student role must not reserve file storage.',
		'restricted',
		'own-work'
	);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

-- Abort directly from uploading.

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000005',
			'abort-uploading.pdf',
			'application/pdf',
			1024,
			NULL
		)
	$$,
	'uploading abort fixture can be reserved'
);

RESET ROLE;

SELECT set_config(
	'app.test_abort_uploading_file_id',
	(
		SELECT id::text
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000005'
	),
	true
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.abort_resource_file_upload(
			current_setting(
				'app.test_abort_uploading_file_id'
			)::uuid,
			'R2 write did not complete'
		)
	$$,
	'owner can abort an uploading reservation'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			review_status = 'draft'::public.resource_review_status
			AND submitted_at IS NULL
		FROM public.academic_resources
		WHERE id =
			'20000000-0000-0000-0000-000000000005'
	),
	'abort preserves the editable academic resource'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000005'
	),
	0,
	'abort deletes public file metadata'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM private.resource_storage_objects
		WHERE file_id = current_setting(
			'app.test_abort_uploading_file_id'
		)::uuid
	),
	0,
	'abort deletes the private storage reservation by cascade'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000005'
			AND action = 'storage_aborted'
			AND comment = 'R2 write did not complete'
			AND metadata ->> 'previous_storage_status' = 'uploading'
	),
	1,
	'abort records the uploading compensation event'
);

-- Preserve a failed storage object before cleanup.

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000006',
			'failed-storage.pdf',
			'application/pdf',
			2048,
			NULL
		)
	$$,
	'failed compensation fixture can be reserved'
);

RESET ROLE;

SELECT set_config(
	'app.test_failed_file_id',
	(
		SELECT id::text
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000006'
	),
	true
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000803',
	'authenticated'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.mark_resource_file_failed(
			current_setting('app.test_failed_file_id')::uuid,
			'unauthorized compensation'
		)
	$$),
	'another contributor cannot mark the owner storage as failed'
);

RESET ROLE;

SELECT is(
	(
		SELECT storage_status::text
		FROM private.resource_storage_objects
		WHERE file_id =
			current_setting('app.test_failed_file_id')::uuid
	),
	'uploading',
	'failed compensation denial preserves uploading state'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.mark_resource_file_failed(
			current_setting('app.test_failed_file_id')::uuid,
			'R2 delete also failed'
		)
	$$,
	'owner can preserve a failed storage incident'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			storage_status = 'failed'::public.resource_storage_status
			AND failure_reason = 'R2 delete also failed'
			AND stored_at IS NULL
		FROM private.resource_storage_objects
		WHERE file_id =
			current_setting('app.test_failed_file_id')::uuid
	),
	'failed compensation preserves storage metadata and reason'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_files
		WHERE id = current_setting(
			'app.test_failed_file_id'
		)::uuid
	),
	1,
	'failed compensation preserves public file metadata'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000006'
			AND action = 'storage_failed'
			AND comment = 'R2 delete also failed'
	),
	1,
	'failed compensation records one storage_failed event'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.abort_resource_file_upload(
			current_setting('app.test_failed_file_id')::uuid,
			'manual reconciliation completed'
		)
	$$,
	'owner can abort a failed reservation after reconciliation'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			review_status = 'draft'::public.resource_review_status
			AND submitted_at IS NULL
		FROM public.academic_resources
		WHERE id =
			'20000000-0000-0000-0000-000000000006'
	)
	AND NOT EXISTS (
		SELECT 1
		FROM public.resource_files
		WHERE id = current_setting(
			'app.test_failed_file_id'
		)::uuid
	)
	AND NOT EXISTS (
		SELECT 1
		FROM private.resource_storage_objects
		WHERE file_id = current_setting(
			'app.test_failed_file_id'
		)::uuid
	),
	'aborting failed storage removes metadata but preserves the resource'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000006'
			AND action IN ('storage_failed', 'storage_aborted')
	),
	2,
	'failed reconciliation preserves both audit events'
);

SELECT is(
	(
		SELECT metadata ->> 'previous_storage_status'
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000006'
			AND action = 'storage_aborted'
	),
	'failed',
	'abort records that the previous storage state was failed'
);

-- Reject abort after successful finalization.

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000007',
			'stored.pdf',
			'application/pdf',
			4096,
			NULL
		)
	$$,
	'stored abort fixture can be reserved'
);

RESET ROLE;

SELECT set_config(
	'app.test_stored_file_id',
	(
		SELECT id::text
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000007'
	),
	true
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);

SELECT lives_ok(
	$$
		SELECT public.finalize_resource_file_upload(
			current_setting('app.test_stored_file_id')::uuid,
			'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
			'stored abort fixture'
		)
	$$,
	'stored abort fixture can be finalized'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.abort_resource_file_upload(
			current_setting('app.test_stored_file_id')::uuid,
			'must not abort stored object'
		)
	$$),
	'a stored file cannot be aborted'
);

RESET ROLE;

SELECT ok(
	(
		SELECT
			storage_object.storage_status =
				'stored'::public.resource_storage_status
			AND academic_resource.review_status =
				'pending'::public.resource_review_status
			AND resource_file.sha256 =
				'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.id =
			current_setting('app.test_stored_file_id')::uuid
	),
	'rejected stored abort preserves the completed state'
);

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_review_events
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000007'
			AND action = 'storage_aborted'
	),
	0,
	'rejected stored abort creates no compensation event'
);

-- Role and ownership controls.

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000803',
	'authenticated'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000008',
			'wrong-owner.pdf',
			'application/pdf',
			512,
			NULL
		)
	$$),
	'a contributor cannot reserve a file for another owner'
);

RESET ROLE;

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000008'
	),
	0,
	'wrong-owner reservation leaves no metadata'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000804',
	'authenticated'
);

SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000009',
			'student.pdf',
			'application/pdf',
			512,
			NULL
		)
	$$),
	'a student role cannot reserve upload storage'
);

RESET ROLE;

SELECT is(
	(
		SELECT count(*)::integer
		FROM public.resource_files
		WHERE resource_id =
			'20000000-0000-0000-0000-000000000009'
	),
	0,
	'student reservation denial leaves no metadata'
);

SELECT * FROM finish();

ROLLBACK;
