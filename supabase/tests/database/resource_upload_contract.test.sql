SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT plan(89);

SELECT ok(
	to_regprocedure(
		'public.register_resource_file_upload(uuid,text,public.resource_file_kind,text,text,bigint,text)'
	) IS NOT NULL,
	'canonical seven-argument upload reservation RPC exists'
);

SELECT ok(
	to_regprocedure(
		'public.register_resource_file_upload(uuid,text,text,bigint,text)'
	) IS NULL,
	'previous five-argument reservation RPC was removed'
);

SELECT ok(
	(
		SELECT pg_proc.proargnames = ARRAY[
			'resource_id',
			'display_filename',
			'file_kind',
			'normalized_extension',
			'content_type',
			'byte_size',
			'sha256'
		]::text[]
		FROM pg_proc
		WHERE pg_proc.oid = to_regprocedure(
			'public.register_resource_file_upload(uuid,text,public.resource_file_kind,text,text,bigint,text)'
		)
	),
	'reservation caller can provide canonical metadata but not storage key or version'
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
		'public.register_resource_file_upload(uuid,text,public.resource_file_kind,text,text,bigint,text)',
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
		'public.register_resource_file_upload(uuid,text,public.resource_file_kind,text,text,bigint,text)',
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


SELECT is(
	(
		SELECT array_agg(pg_enum.enumlabel::text ORDER BY pg_enum.enumsortorder)
		FROM pg_enum
		WHERE pg_enum.enumtypid = 'public.resource_file_kind'::regtype
	),
	ARRAY['pdf', 'image', 'markdown', 'tex', 'text', 'source']::text[],
	'resource_file_kind contains the exact canonical file kinds'
);

SELECT is(
	(
		SELECT array_agg(pg_enum.enumlabel::text ORDER BY pg_enum.enumsortorder)
		FROM pg_enum
		WHERE pg_enum.enumtypid = 'public.resource_storage_key_version'::regtype
	),
	ARRAY['legacy_pdf_v1', 'generic_v2']::text[],
	'resource_storage_key_version contains both explicit layouts'
);

SELECT ok(
	(
		SELECT count(*) = 3
			AND bool_and(information_schema.columns.is_nullable = 'NO')
			AND bool_and(information_schema.columns.column_default IS NULL)
		FROM information_schema.columns
		WHERE table_schema = 'public'
			AND table_name = 'resource_files'
			AND column_name IN (
				'file_kind',
				'normalized_extension',
				'storage_key_version'
			)
	),
	'canonical ResourceFile columns are required and have no legacy defaults'
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
	NOT EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname IN (
				'resource_files_content_type_pdf_check',
				'resource_files_display_filename_pdf_check',
				'resource_files_stage_4c0b_pdf_only_check'
			)
	),
	'obsolete PDF-only constraints were removed'
);

SELECT ok(
	EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conrelid = 'public.resource_files'::regclass
			AND conname = 'resource_files_stage_4c3_canonical_metadata_check'
			AND pg_get_constraintdef(oid) LIKE '%application/pdf%'
			AND pg_get_constraintdef(oid) LIKE '%image/png%'
			AND pg_get_constraintdef(oid) LIKE '%image/jpeg%'
	),
	'Stage 4C.3 canonical PDF/PNG/JPEG table constraint exists'
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
		'20000000-0000-0000-0000-000000000016',
		'00000000-0000-0000-0000-000000000802',
		'course:images', '2026-1', 'notes', 'PNG upload',
		'Canonical PNG reservation fixture.', 'restricted', 'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000017',
		'00000000-0000-0000-0000-000000000802',
		'course:images', '2026-1', 'notes', 'JPG upload',
		'Canonical JPG reservation fixture.', 'restricted', 'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000018',
		'00000000-0000-0000-0000-000000000802',
		'course:images', '2026-1', 'notes', 'JPEG upload',
		'Canonical JPEG reservation fixture.', 'restricted', 'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000019',
		'00000000-0000-0000-0000-000000000802',
		'course:images', '2026-1', 'notes', 'Invalid image metadata',
		'Rejected canonical metadata fixture.', 'restricted', 'own-work'
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
		SELECT resource_file.file_kind = 'pdf'::public.resource_file_kind
			AND resource_file.normalized_extension = '.pdf'
			AND resource_file.content_type = 'application/pdf'
			AND resource_file.storage_key_version =
				'generic_v2'::public.resource_storage_key_version
			AND storage_object.storage_key =
				'resources/'
				|| resource_file.resource_id::text
				|| '/'
				|| resource_file.id::text
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id =
			'20000000-0000-0000-0000-000000000001'
	),
	'new reservation stores canonical PDF metadata and derives a suffixless generic_v2 key'
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'20000000-0000-0000-0000-000000000016',
			'Diagram.PNG', 'image', '.png', 'image/png', 2048, NULL
		)
	$$,
	'uppercase PNG filename with canonical metadata reserves successfully'
);
SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000017',
			'Photo.JPG', 'image', '.jpg', 'image/jpeg', 4096, NULL
		)
	$$,
	'uppercase JPG filename with canonical metadata reserves successfully'
);
SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000018',
			'Photo.jpeg', 'image', '.jpeg', 'image/jpeg', 8192, NULL
		)
	$$,
	'JPEG filename with canonical metadata reserves successfully'
);

RESET ROLE;
SELECT ok(
	(
		SELECT resource_file.file_kind = 'image'::public.resource_file_kind
			AND resource_file.normalized_extension = '.png'
			AND resource_file.content_type = 'image/png'
			AND resource_file.storage_key_version = 'generic_v2'
			AND storage_object.storage_key =
				'resources/' || resource_file.resource_id::text || '/' || resource_file.id::text
			AND storage_object.storage_key !~ '[.](png|jpe?g)$'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id = '20000000-0000-0000-0000-000000000016'
	),
	'PNG reservation stores canonical metadata and a suffixless generic_v2 key'
);
SELECT ok(
	(
		SELECT resource_file.file_kind = 'image'::public.resource_file_kind
			AND resource_file.normalized_extension = '.jpg'
			AND resource_file.content_type = 'image/jpeg'
			AND resource_file.storage_key_version = 'generic_v2'
			AND storage_object.storage_key =
				'resources/' || resource_file.resource_id::text || '/' || resource_file.id::text
			AND storage_object.storage_key !~ '[.](png|jpe?g)$'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id = '20000000-0000-0000-0000-000000000017'
	),
	'JPG reservation stores canonical metadata and a suffixless generic_v2 key'
);
SELECT ok(
	(
		SELECT resource_file.file_kind = 'image'::public.resource_file_kind
			AND resource_file.normalized_extension = '.jpeg'
			AND resource_file.content_type = 'image/jpeg'
			AND resource_file.storage_key_version = 'generic_v2'
			AND storage_object.storage_key =
				'resources/' || resource_file.resource_id::text || '/' || resource_file.id::text
			AND storage_object.storage_key !~ '[.](png|jpe?g)$'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id = '20000000-0000-0000-0000-000000000018'
	),
	'JPEG reservation stores canonical metadata and a suffixless generic_v2 key'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'bad.png', 'image', '.png', 'image/jpeg', 512, NULL
		)
	$$),
	'PNG metadata with image/jpeg is rejected'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'bad.jpg', 'image', '.jpg', 'image/png', 512, NULL
		)
	$$),
	'JPEG metadata with image/png is rejected'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'bad.pdf', 'image', '.pdf', 'application/pdf', 512, NULL
		)
	$$),
	'image kind with PDF extension is rejected'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'bad.png', 'pdf', '.png', 'image/png', 512, NULL
		)
	$$),
	'PDF kind with PNG extension is rejected'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'contradiction.jpeg', 'image', '.jpg', 'image/jpeg', 512, NULL
		)
	$$),
	'filename suffix contradicting normalized extension is rejected'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'future.md', 'markdown', '.md', 'text/plain', 512, NULL
		)
	$$),
	'Markdown metadata remains rejected in Stage 4C.3'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'future.tex', 'tex', '.tex', 'text/plain', 512, NULL
		)
	$$),
	'TeX metadata remains rejected in Stage 4C.3'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'future.txt', 'text', '.txt', 'text/plain', 512, NULL
		)
	$$),
	'text metadata remains rejected in Stage 4C.3'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000019',
			'future.py', 'source', '.py', 'text/plain', 512, NULL
		)
	$$),
	'source metadata remains rejected in Stage 4C.3'
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
			'20000000-0000-0000-0000-000000000003',
			'atomic.pdf',
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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
			'pdf'::public.resource_file_kind,
			'.pdf',
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

RESET ROLE;
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
		'20000000-0000-0000-0000-000000000010',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'notes',
		'Open-license upload',
		'Open-license existing PDF saga fixture.',
		'public',
		'open-license'
	),
	(
		'20000000-0000-0000-0000-000000000011',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'notes',
		'Public-domain upload',
		'Public-domain existing PDF saga fixture.',
		'public',
		'public-domain'
	),
	(
		'20000000-0000-0000-0000-000000000012',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'book-reference',
		'Bibliographic upload denial',
		'Bibliographic reference cannot store a main file.',
		'restricted',
		'bibliographic-reference-only'
	),
	(
		'20000000-0000-0000-0000-000000000013',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'notes',
		'Copyright upload denial',
		'Copyright-restricted resource cannot store a main file.',
		'restricted',
		'copyright-restricted'
	);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);
SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000010',
			'open-license.pdf',
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			4096,
			'1111111111111111111111111111111111111111111111111111111111111111'
		)
	$$,
	'open-license uses the existing PDF reservation path'
);
SELECT lives_ok(
	$$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id FROM public.resource_files
				WHERE resource_id = '20000000-0000-0000-0000-000000000010'
			),
			'1111111111111111111111111111111111111111111111111111111111111111',
			'open-license finalization'
		)
	$$,
	'open-license uses the existing atomic PDF finalization path'
);

RESET ROLE;
SELECT ok(
	(
		SELECT resource_file.content_type = 'application/pdf'
			AND resource_file.display_filename = 'open-license.pdf'
			AND resource_file.byte_size = 4096
			AND resource_file.sha256 = '1111111111111111111111111111111111111111111111111111111111111111'
			AND storage_object.storage_status = 'stored'
			AND storage_object.storage_key =
				'resources/' || resource_file.resource_id::text || '/' || resource_file.id::text
			AND academic_resource.review_status = 'pending'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.resource_id = '20000000-0000-0000-0000-000000000010'
	),
	'open-license preserves exact PDF metadata hash size private key and pending transition'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);
SELECT lives_ok(
	$$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000011',
			'public-domain.pdf',
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			8192,
			NULL
		)
	$$,
	'public-domain uses the existing PDF reservation path'
);
SELECT lives_ok(
	$$
		SELECT public.finalize_resource_file_upload(
			(
				SELECT id FROM public.resource_files
				WHERE resource_id = '20000000-0000-0000-0000-000000000011'
			),
			'2222222222222222222222222222222222222222222222222222222222222222',
			'public-domain finalization'
		)
	$$,
	'public-domain uses the existing atomic PDF finalization path'
);

RESET ROLE;
SELECT ok(
	(
		SELECT resource_file.content_type = 'application/pdf'
			AND resource_file.display_filename = 'public-domain.pdf'
			AND resource_file.byte_size = 8192
			AND resource_file.sha256 = '2222222222222222222222222222222222222222222222222222222222222222'
			AND storage_object.storage_status = 'stored'
			AND storage_object.storage_key =
				'resources/' || resource_file.resource_id::text || '/' || resource_file.id::text
			AND academic_resource.review_status = 'pending'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		INNER JOIN public.academic_resources AS academic_resource
			ON academic_resource.id = resource_file.resource_id
		WHERE resource_file.resource_id = '20000000-0000-0000-0000-000000000011'
	),
	'public-domain preserves exact PDF metadata hash size private key and pending transition'
);

SET LOCAL ROLE authenticated;
SELECT pg_temp.set_request_context(
	'00000000-0000-0000-0000-000000000802',
	'authenticated'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000012',
			'bibliographic.pdf',
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			512,
			NULL
		)
	$$),
	'bibliographic-reference-only remains forbidden for stored files'
);
SELECT ok(
	NOT pg_temp.try_sql($$
		SELECT public.register_resource_file_upload(
			'20000000-0000-0000-0000-000000000013',
			'copyright.pdf',
			'pdf'::public.resource_file_kind,
			'.pdf',
			'application/pdf',
			512,
			NULL
		)
	$$),
	'copyright-restricted remains forbidden for stored files'
);

RESET ROLE;

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
		'20000000-0000-0000-0000-000000000014',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'notes',
		'Legacy layout fixture',
		'Represents an existing PDF object without rewriting its key.',
		'restricted',
		'own-work'
	),
	(
		'20000000-0000-0000-0000-000000000015',
		'00000000-0000-0000-0000-000000000802',
		'course:rights',
		'2026-1',
		'notes',
		'Mismatched layout fixture',
		'Rejects a storage key that contradicts canonical metadata.',
		'restricted',
		'own-work'
	);

SELECT lives_ok(
	$$
		WITH legacy_file AS (
			INSERT INTO public.resource_files (
				id,
				resource_id,
				uploaded_by,
				display_filename,
				file_kind,
				normalized_extension,
				content_type,
				byte_size,
				storage_key_version
			)
			VALUES (
				'30000000-0000-0000-0000-000000000014',
				'20000000-0000-0000-0000-000000000014',
				'00000000-0000-0000-0000-000000000802',
				'legacy.pdf',
				'pdf'::public.resource_file_kind,
				'.pdf',
				'application/pdf',
				1024,
				'legacy_pdf_v1'::public.resource_storage_key_version
			)
			RETURNING id
		)
		INSERT INTO private.resource_storage_objects (file_id, storage_key)
		SELECT
			legacy_file.id,
			'resources/20000000-0000-0000-0000-000000000014/'
				|| legacy_file.id::text
				|| '.pdf'
		FROM legacy_file
	$$,
	'a valid legacy_pdf_v1 ResourceFile and private key remain representable'
);

SELECT ok(
	(
		SELECT resource_file.storage_key_version =
				'legacy_pdf_v1'::public.resource_storage_key_version
			AND storage_object.storage_key =
				'resources/20000000-0000-0000-0000-000000000014/'
				|| resource_file.id::text
				|| '.pdf'
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.id = '30000000-0000-0000-0000-000000000014'
	),
	'legacy metadata retains its explicit version and suffixed storage key'
);

INSERT INTO public.resource_files (
	id,
	resource_id,
	uploaded_by,
	display_filename,
	file_kind,
	normalized_extension,
	content_type,
	byte_size,
	storage_key_version
)
VALUES (
	'30000000-0000-0000-0000-000000000015',
	'20000000-0000-0000-0000-000000000015',
	'00000000-0000-0000-0000-000000000802',
	'mismatch.pdf',
	'pdf'::public.resource_file_kind,
	'.pdf',
	'application/pdf',
	1024,
	'generic_v2'::public.resource_storage_key_version
);

SELECT ok(
	NOT pg_temp.try_sql($$
		INSERT INTO private.resource_storage_objects (file_id, storage_key)
		VALUES (
			'30000000-0000-0000-0000-000000000015',
			'resources/20000000-0000-0000-0000-000000000015/'
				|| '30000000-0000-0000-0000-000000000015.pdf'
		)
	$$),
	'a storage key that contradicts generic_v2 metadata is rejected'
);

SELECT * FROM finish();

ROLLBACK;
