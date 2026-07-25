BEGIN;

CREATE TYPE public.resource_file_kind AS ENUM (
	'pdf',
	'image',
	'markdown',
	'tex',
	'text',
	'source'
);

CREATE TYPE public.resource_storage_key_version AS ENUM (
	'legacy_pdf_v1',
	'generic_v2'
);

ALTER TABLE public.resource_files
ADD COLUMN file_kind public.resource_file_kind
	DEFAULT 'pdf'::public.resource_file_kind,
ADD COLUMN normalized_extension text DEFAULT '.pdf',
ADD COLUMN storage_key_version public.resource_storage_key_version
	DEFAULT 'legacy_pdf_v1'::public.resource_storage_key_version;

ALTER TABLE public.resource_files
ALTER COLUMN file_kind DROP DEFAULT,
ALTER COLUMN normalized_extension DROP DEFAULT,
ALTER COLUMN storage_key_version DROP DEFAULT,
ALTER COLUMN file_kind SET NOT NULL,
ALTER COLUMN normalized_extension SET NOT NULL,
ALTER COLUMN storage_key_version SET NOT NULL;

ALTER TABLE public.resource_files
ADD CONSTRAINT resource_files_normalized_extension_check CHECK (
	normalized_extension = lower(normalized_extension)
	AND normalized_extension = btrim(normalized_extension)
	AND normalized_extension ~ '^[.][a-z0-9]+$'
),
ADD CONSTRAINT resource_files_stage_4c0b_pdf_only_check CHECK (
	file_kind = 'pdf'::public.resource_file_kind
	AND normalized_extension = '.pdf'
	AND content_type = 'application/pdf'
);

CREATE OR REPLACE FUNCTION private.expected_resource_storage_key(
	resource_id uuid,
	file_id uuid,
	storage_key_version public.resource_storage_key_version
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	base_key text :=
		'resources/' || resource_id::text || '/' || file_id::text;
BEGIN
	CASE storage_key_version
		WHEN 'legacy_pdf_v1'::public.resource_storage_key_version THEN
			RETURN base_key || '.pdf';
		WHEN 'generic_v2'::public.resource_storage_key_version THEN
			RETURN base_key;
		ELSE
			RAISE EXCEPTION 'unsupported resource storage key version'
				USING ERRCODE = '23514';
	END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION private.set_resource_file_defaults_and_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	IF TG_OP = 'INSERT' THEN
		NEW.uploaded_by := COALESCE(NEW.uploaded_by, auth.uid());
		NEW.created_at := COALESCE(NEW.created_at, now());
		NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
	END IF;

	IF TG_OP = 'UPDATE' THEN
		IF NEW.id IS DISTINCT FROM OLD.id
			OR NEW.resource_id IS DISTINCT FROM OLD.resource_id
			OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by
			OR NEW.storage_key_version IS DISTINCT FROM OLD.storage_key_version THEN
			RAISE EXCEPTION 'resource file identity fields are immutable' USING ERRCODE = '42501';
		END IF;

		NEW.created_at := OLD.created_at;
		NEW.updated_at := now();
	END IF;

	IF NEW.uploaded_by IS NULL THEN
		RAISE EXCEPTION 'resource file uploader is required' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.set_resource_storage_object_defaults_and_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	resource_file_record public.resource_files%ROWTYPE;
	expected_storage_key text;
BEGIN
	IF TG_OP = 'INSERT' THEN
		NEW.created_at := COALESCE(NEW.created_at, now());
		NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
	END IF;

	IF TG_OP = 'UPDATE' THEN
		IF NEW.file_id IS DISTINCT FROM OLD.file_id OR NEW.storage_key IS DISTINCT FROM OLD.storage_key THEN
			RAISE EXCEPTION 'resource storage object identity fields are immutable' USING ERRCODE = '42501';
		END IF;

		NEW.created_at := OLD.created_at;
		NEW.updated_at := now();
	END IF;

	SELECT resource_file.*
	INTO resource_file_record
	FROM public.resource_files AS resource_file
	WHERE resource_file.id = NEW.file_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file does not exist' USING ERRCODE = '23503';
	END IF;

	expected_storage_key := private.expected_resource_storage_key(
		resource_file_record.resource_id,
		resource_file_record.id,
		resource_file_record.storage_key_version
	);

	IF NEW.storage_key IS DISTINCT FROM expected_storage_key THEN
		RAISE EXCEPTION 'resource storage key does not match its declared layout version'
			USING ERRCODE = '23514';
	END IF;

	IF NEW.storage_status = 'stored'::public.resource_storage_status AND NEW.stored_at IS NULL THEN
		RAISE EXCEPTION 'stored resource objects require stored_at' USING ERRCODE = '23514';
	END IF;

	IF NEW.storage_status = 'deleted'::public.resource_storage_status AND NEW.deleted_at IS NULL THEN
		RAISE EXCEPTION 'deleted resource objects require deleted_at' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS public.register_resource_file_upload(
	uuid,
	text,
	text,
	bigint,
	text
);

CREATE FUNCTION public.register_resource_file_upload(
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

	IF requested_file_kind IS DISTINCT FROM 'pdf'::public.resource_file_kind
		OR requested_normalized_extension IS DISTINCT FROM '.pdf'
		OR requested_content_type IS DISTINCT FROM 'application/pdf'
		OR lower(normalized_display_filename) NOT LIKE '%.pdf' THEN
		RAISE EXCEPTION 'only canonical PDF metadata is supported' USING ERRCODE = '23514';
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

REVOKE ALL ON TYPE public.resource_file_kind FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.resource_storage_key_version FROM PUBLIC, anon, authenticated;
GRANT USAGE ON TYPE public.resource_file_kind TO anon, authenticated;
GRANT USAGE ON TYPE public.resource_storage_key_version TO anon, authenticated;

REVOKE ALL
ON FUNCTION private.expected_resource_storage_key(
	uuid,
	uuid,
	public.resource_storage_key_version
)
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.set_resource_file_defaults_and_validate()
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.set_resource_storage_object_defaults_and_validate()
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION public.register_resource_file_upload(
	uuid,
	text,
	public.resource_file_kind,
	text,
	text,
	bigint,
	text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.register_resource_file_upload(
	uuid,
	text,
	public.resource_file_kind,
	text,
	text,
	bigint,
	text
)
TO authenticated;

COMMIT;
