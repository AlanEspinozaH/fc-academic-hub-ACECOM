BEGIN;

-- Stage 4B.2 initially supports exactly one private PDF per academic resource.
ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_one_file_per_resource_key
UNIQUE (resource_id);

-- The unique constraint already supplies an index for lookups by resource_id.
DROP INDEX IF EXISTS public.resource_files_resource_id_idx;

ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_content_type_pdf_check
CHECK (content_type = 'application/pdf');

ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_display_filename_pdf_check
CHECK (lower(display_filename) LIKE '%.pdf');

ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_byte_size_max_check
CHECK (byte_size <= 10000000);

-- Preserve existing audit actions and add the explicit reservation-abort event.
ALTER TABLE public.resource_review_events
DROP CONSTRAINT resource_review_events_action_check;

ALTER TABLE public.resource_review_events
ADD CONSTRAINT resource_review_events_action_check
CHECK (
	action IN (
		'submit',
		'approve',
		'reject',
		'storage_stored',
		'storage_failed',
		'storage_aborted'
	)
);

-- The old signature accepted an arbitrary storage_key from an authenticated
-- caller. Stage 4B.2 derives the private key from trusted database identifiers.
DROP FUNCTION IF EXISTS public.register_resource_file_upload(
	uuid,
	text,
	text,
	bigint,
	text,
	text
);

CREATE OR REPLACE FUNCTION public.register_resource_file_upload(
	resource_id uuid,
	display_filename text,
	content_type text,
	byte_size bigint,
	sha256 text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_resource_id uuid := resource_id;
	normalized_display_filename text := NULLIF(btrim(display_filename), '');
	normalized_content_type text := NULLIF(btrim(content_type), '');
	normalized_sha256 text := lower(NULLIF(btrim(sha256), ''));
	resource_record public.academic_resources%ROWTYPE;
	new_file_id uuid;
	generated_storage_key text;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources AS academic_resource
	WHERE academic_resource.id = requested_resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF NOT private.can_edit_academic_resource(
		resource_record.owner_user_id,
		resource_record.review_status
	) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	IF resource_record.rights_status IN (
		'bibliographic-reference-only'::public.resource_rights_status,
		'copyright-restricted'::public.resource_rights_status
	) THEN
		RAISE EXCEPTION 'resource rights do not allow stored files' USING ERRCODE = '23514';
	END IF;

	IF normalized_display_filename IS NULL
		OR normalized_content_type IS NULL
		OR byte_size IS NULL THEN
		RAISE EXCEPTION 'valid file metadata is required' USING ERRCODE = '23514';
	END IF;

	IF byte_size <= 0 OR byte_size > 10000000 THEN
		RAISE EXCEPTION 'file size must be between 1 and 10000000 bytes'
			USING ERRCODE = '23514';
	END IF;

	IF normalized_content_type <> 'application/pdf'
		OR lower(normalized_display_filename) NOT LIKE '%.pdf' THEN
		RAISE EXCEPTION 'only PDF files are supported' USING ERRCODE = '23514';
	END IF;

	IF normalized_sha256 IS NOT NULL AND normalized_sha256 !~ '^[0-9a-f]{64}$' THEN
		RAISE EXCEPTION 'sha256 must be 64 hexadecimal characters' USING ERRCODE = '23514';
	END IF;

	INSERT INTO public.resource_files (
		resource_id,
		uploaded_by,
		display_filename,
		content_type,
		byte_size,
		sha256
	)
	VALUES (
		resource_record.id,
		actor_user_id,
		normalized_display_filename,
		normalized_content_type,
		byte_size,
		normalized_sha256
	)
	RETURNING id INTO new_file_id;

	generated_storage_key :=
		'resources/'
		|| resource_record.id::text
		|| '/'
		|| new_file_id::text
		|| '.pdf';

	INSERT INTO private.resource_storage_objects (
		file_id,
		storage_key,
		storage_status
	)
	VALUES (
		new_file_id,
		generated_storage_key,
		'uploading'::public.resource_storage_status
	);

	RETURN new_file_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_resource_file_upload(
	file_id uuid,
	sha256 text,
	comment text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_file_id uuid := file_id;
	normalized_sha256 text := lower(NULLIF(btrim(sha256), ''));
	normalized_comment text := NULLIF(btrim(comment), '');
	requested_resource_id uuid;
	resource_record public.academic_resources%ROWTYPE;
	file_record public.resource_files%ROWTYPE;
	storage_record private.resource_storage_objects%ROWTYPE;
	transition_at timestamptz := now();
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF normalized_sha256 IS NULL OR normalized_sha256 !~ '^[0-9a-f]{64}$' THEN
		RAISE EXCEPTION 'valid sha256 is required' USING ERRCODE = '23514';
	END IF;

	SELECT resource_file.resource_id
	INTO requested_resource_id
	FROM public.resource_files AS resource_file
	WHERE resource_file.id = requested_file_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources AS academic_resource
	WHERE academic_resource.id = requested_resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO file_record
	FROM public.resource_files AS resource_file
	WHERE resource_file.id = requested_file_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO storage_record
	FROM private.resource_storage_objects AS storage_object
	WHERE storage_object.file_id = file_record.id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource storage object does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF resource_record.owner_user_id <> actor_user_id
		OR file_record.uploaded_by <> actor_user_id
		OR NOT private.has_any_role(
			ARRAY[
				'contributor',
				'reviewer',
				'moderator',
				'administrator'
			]::public.app_role[]
		) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	IF storage_record.storage_status = 'stored'::public.resource_storage_status THEN
		IF resource_record.review_status = 'pending'::public.resource_review_status
			AND file_record.sha256 = normalized_sha256 THEN
			RETURN file_record.id;
		END IF;

		IF file_record.sha256 IS DISTINCT FROM normalized_sha256 THEN
			RAISE EXCEPTION 'resource file sha256 does not match stored hash' USING ERRCODE = '23514';
		END IF;

		RAISE EXCEPTION 'resource file final state is inconsistent' USING ERRCODE = '23514';
	END IF;

	IF resource_record.review_status NOT IN (
		'draft'::public.resource_review_status,
		'rejected'::public.resource_review_status
	) THEN
		RAISE EXCEPTION 'only draft or rejected resources can finalize uploads' USING ERRCODE = '23514';
	END IF;

	IF storage_record.storage_status <> 'uploading'::public.resource_storage_status THEN
		RAISE EXCEPTION 'resource file is not awaiting storage' USING ERRCODE = '23514';
	END IF;

	IF NOT private.resource_rights_allow_stored_files(resource_record.rights_status) THEN
		RAISE EXCEPTION 'resource rights do not allow stored files' USING ERRCODE = '23514';
	END IF;

	IF file_record.sha256 IS NOT NULL AND file_record.sha256 <> normalized_sha256 THEN
		RAISE EXCEPTION 'resource file sha256 does not match reserved hash' USING ERRCODE = '23514';
	END IF;

	UPDATE public.resource_files
	SET sha256 = normalized_sha256
	WHERE public.resource_files.id = file_record.id;

	UPDATE private.resource_storage_objects
	SET storage_status = 'stored'::public.resource_storage_status,
		stored_at = transition_at,
		failure_reason = NULL,
		delete_requested_at = NULL,
		deleted_at = NULL
	WHERE private.resource_storage_objects.file_id = file_record.id;

	PERFORM set_config('app.resource_review_transition', 'on', true);

	UPDATE public.academic_resources
	SET review_status = 'pending'::public.resource_review_status,
		submitted_at = transition_at,
		reviewed_by = NULL,
		reviewed_at = NULL
	WHERE public.academic_resources.id = resource_record.id;

	PERFORM set_config('app.resource_review_transition', '', true);

	INSERT INTO public.resource_review_events (
		resource_id,
		actor_user_id,
		from_status,
		to_status,
		action,
		comment,
		metadata,
		occurred_at
	)
	VALUES (
		resource_record.id,
		actor_user_id,
		resource_record.review_status,
		resource_record.review_status,
		'storage_stored',
		NULL,
		jsonb_build_object('file_id', file_record.id),
		transition_at
	);

	INSERT INTO public.resource_review_events (
		resource_id,
		actor_user_id,
		from_status,
		to_status,
		action,
		comment,
		metadata,
		occurred_at
	)
	VALUES (
		resource_record.id,
		actor_user_id,
		resource_record.review_status,
		'pending'::public.resource_review_status,
		'submit',
		normalized_comment,
		jsonb_build_object('file_id', file_record.id),
		transition_at
	);

	RETURN file_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.abort_resource_file_upload(
	file_id uuid,
	reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_file_id uuid := file_id;
	normalized_reason text := NULLIF(btrim(reason), '');
	requested_resource_id uuid;
	resource_record public.academic_resources%ROWTYPE;
	file_record public.resource_files%ROWTYPE;
	storage_record private.resource_storage_objects%ROWTYPE;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.has_any_role(
		ARRAY[
			'contributor',
			'reviewer',
			'moderator',
			'administrator'
		]::public.app_role[]
	) THEN
		RAISE EXCEPTION 'contributor role required' USING ERRCODE = '42501';
	END IF;

	SELECT resource_file.resource_id
	INTO requested_resource_id
	FROM public.resource_files AS resource_file
	WHERE resource_file.id = requested_file_id;

	IF NOT FOUND THEN
		RETURN requested_file_id;
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources AS academic_resource
	WHERE academic_resource.id = requested_resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO file_record
	FROM public.resource_files AS resource_file
	WHERE resource_file.id = requested_file_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RETURN requested_file_id;
	END IF;

	SELECT *
	INTO storage_record
	FROM private.resource_storage_objects AS storage_object
	WHERE storage_object.file_id = file_record.id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource storage object does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF resource_record.owner_user_id <> actor_user_id
		OR file_record.uploaded_by <> actor_user_id THEN
		RAISE EXCEPTION 'resource owner uploader role required' USING ERRCODE = '42501';
	END IF;

	IF resource_record.review_status NOT IN (
		'draft'::public.resource_review_status,
		'rejected'::public.resource_review_status
	) THEN
		RAISE EXCEPTION 'only draft or rejected resources can abort uploads' USING ERRCODE = '23514';
	END IF;

	IF storage_record.storage_status = 'stored'::public.resource_storage_status THEN
		RAISE EXCEPTION 'stored resource files cannot be aborted' USING ERRCODE = '23514';
	END IF;

	IF storage_record.storage_status NOT IN (
		'uploading'::public.resource_storage_status,
		'failed'::public.resource_storage_status
	) THEN
		RAISE EXCEPTION 'resource file cannot be aborted from this storage state' USING ERRCODE = '23514';
	END IF;

	INSERT INTO public.resource_review_events (
		resource_id,
		actor_user_id,
		from_status,
		to_status,
		action,
		comment,
		metadata
	)
	VALUES (
		resource_record.id,
		actor_user_id,
		resource_record.review_status,
		resource_record.review_status,
		'storage_aborted',
		normalized_reason,
		jsonb_build_object(
			'file_id',
			file_record.id,
			'previous_storage_status',
			storage_record.storage_status::text
		)
	);

	DELETE FROM public.resource_files
	WHERE public.resource_files.id = file_record.id;

	RETURN file_record.id;
END;
$$;

REVOKE EXECUTE
ON FUNCTION public.mark_resource_file_stored(uuid, text)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.mark_resource_file_failed(uuid, text)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.register_resource_file_upload(uuid, text, text, bigint, text)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.finalize_resource_file_upload(uuid, text, text)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.abort_resource_file_upload(uuid, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.register_resource_file_upload(uuid, text, text, bigint, text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.finalize_resource_file_upload(uuid, text, text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.abort_resource_file_upload(uuid, text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.mark_resource_file_failed(uuid, text)
TO authenticated;

COMMIT;
