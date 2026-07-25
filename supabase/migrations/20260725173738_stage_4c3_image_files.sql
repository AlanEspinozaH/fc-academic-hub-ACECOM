BEGIN;

ALTER TABLE public.resource_files
DROP CONSTRAINT IF EXISTS resource_files_content_type_pdf_check,
DROP CONSTRAINT IF EXISTS resource_files_display_filename_pdf_check,
DROP CONSTRAINT IF EXISTS resource_files_stage_4c0b_pdf_only_check;

ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_stage_4c3_canonical_metadata_check CHECK (
	(
		file_kind = 'pdf'::public.resource_file_kind
		AND normalized_extension = '.pdf'
		AND content_type = 'application/pdf'
		AND right(lower(display_filename), 4) = '.pdf'
	)
	OR (
		storage_key_version = 'generic_v2'::public.resource_storage_key_version
		AND file_kind = 'image'::public.resource_file_kind
		AND normalized_extension = '.png'
		AND content_type = 'image/png'
		AND right(lower(display_filename), 4) = '.png'
	)
	OR (
		storage_key_version = 'generic_v2'::public.resource_storage_key_version
		AND file_kind = 'image'::public.resource_file_kind
		AND normalized_extension = '.jpg'
		AND content_type = 'image/jpeg'
		AND right(lower(display_filename), 4) = '.jpg'
	)
	OR (
		storage_key_version = 'generic_v2'::public.resource_storage_key_version
		AND file_kind = 'image'::public.resource_file_kind
		AND normalized_extension = '.jpeg'
		AND content_type = 'image/jpeg'
		AND right(lower(display_filename), 5) = '.jpeg'
	)
);

CREATE OR REPLACE FUNCTION public.register_resource_file_upload(
	resource_id uuid,
	display_filename text,
	file_kind public.resource_file_kind,
	normalized_extension text,
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
	requested_file_kind public.resource_file_kind := file_kind;
	requested_normalized_extension text := normalized_extension;
	requested_content_type text := content_type;
	normalized_display_filename text := NULLIF(btrim(display_filename), '');
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

	IF NOT private.resource_rights_allow_stored_files(resource_record.rights_status) THEN
		RAISE EXCEPTION 'resource rights do not allow stored files' USING ERRCODE = '23514';
	END IF;

	IF normalized_display_filename IS NULL OR byte_size IS NULL THEN
		RAISE EXCEPTION 'valid file metadata is required' USING ERRCODE = '23514';
	END IF;

	IF byte_size <= 0 OR byte_size > 10000000 THEN
		RAISE EXCEPTION 'file size must be between 1 and 10000000 bytes'
			USING ERRCODE = '23514';
	END IF;

	IF NOT (
		(
			requested_file_kind IS NOT DISTINCT FROM 'pdf'::public.resource_file_kind
			AND requested_normalized_extension IS NOT DISTINCT FROM '.pdf'
			AND requested_content_type IS NOT DISTINCT FROM 'application/pdf'
			AND right(lower(normalized_display_filename), 4) = '.pdf'
		)
		OR (
			requested_file_kind IS NOT DISTINCT FROM 'image'::public.resource_file_kind
			AND requested_normalized_extension IS NOT DISTINCT FROM '.png'
			AND requested_content_type IS NOT DISTINCT FROM 'image/png'
			AND right(lower(normalized_display_filename), 4) = '.png'
		)
		OR (
			requested_file_kind IS NOT DISTINCT FROM 'image'::public.resource_file_kind
			AND requested_normalized_extension IS NOT DISTINCT FROM '.jpg'
			AND requested_content_type IS NOT DISTINCT FROM 'image/jpeg'
			AND right(lower(normalized_display_filename), 4) = '.jpg'
		)
		OR (
			requested_file_kind IS NOT DISTINCT FROM 'image'::public.resource_file_kind
			AND requested_normalized_extension IS NOT DISTINCT FROM '.jpeg'
			AND requested_content_type IS NOT DISTINCT FROM 'image/jpeg'
			AND right(lower(normalized_display_filename), 5) = '.jpeg'
		)
	) THEN
		RAISE EXCEPTION 'unsupported or non-canonical resource file metadata'
			USING ERRCODE = '23514';
	END IF;

	IF normalized_sha256 IS NOT NULL AND normalized_sha256 !~ '^[0-9a-f]{64}$' THEN
		RAISE EXCEPTION 'sha256 must be 64 hexadecimal characters' USING ERRCODE = '23514';
	END IF;

	INSERT INTO public.resource_files (
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
	VALUES (
		resource_record.id,
		actor_user_id,
		normalized_display_filename,
		requested_file_kind,
		requested_normalized_extension,
		requested_content_type,
		byte_size,
		normalized_sha256,
		'generic_v2'::public.resource_storage_key_version
	)
	RETURNING id INTO new_file_id;

	generated_storage_key := private.expected_resource_storage_key(
		resource_record.id,
		new_file_id,
		'generic_v2'::public.resource_storage_key_version
	);

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

COMMIT;
