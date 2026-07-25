BEGIN;

CREATE TYPE public.resource_file_read_descriptor AS (
	resource_id uuid,
	file_id uuid,
	display_filename text,
	file_kind public.resource_file_kind,
	normalized_extension text,
	content_type text,
	byte_size bigint,
	sha256 text,
	storage_key_version public.resource_storage_key_version
);

CREATE FUNCTION public.get_resource_file_read_descriptor(
	resource_id uuid,
	file_id uuid
)
RETURNS SETOF public.resource_file_read_descriptor
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT
		resource_file.resource_id,
		resource_file.id,
		resource_file.display_filename,
		resource_file.file_kind,
		resource_file.normalized_extension,
		resource_file.content_type,
		resource_file.byte_size,
		resource_file.sha256,
		resource_file.storage_key_version
	FROM public.resource_files AS resource_file
	INNER JOIN private.resource_storage_objects AS storage_object
		ON storage_object.file_id = resource_file.id
	WHERE resource_file.resource_id = $1
		AND resource_file.id = $2
		AND storage_object.storage_status = 'stored'::public.resource_storage_status
		AND private.can_read_resource_by_id($1);
$$;

REVOKE ALL ON TYPE public.resource_file_read_descriptor FROM PUBLIC, anon, authenticated;
GRANT USAGE ON TYPE public.resource_file_read_descriptor TO anon, authenticated;

REVOKE ALL
ON FUNCTION public.get_resource_file_read_descriptor(uuid, uuid)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.get_resource_file_read_descriptor(uuid, uuid)
TO anon, authenticated;

COMMIT;
