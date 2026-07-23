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

SELECT * FROM finish();

ROLLBACK;
