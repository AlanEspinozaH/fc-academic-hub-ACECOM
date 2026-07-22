BEGIN;

DO $$
BEGIN
	CREATE TYPE public.resource_review_status AS ENUM (
		'draft',
		'pending',
		'approved',
		'rejected'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
	CREATE TYPE public.resource_storage_status AS ENUM (
		'uploading',
		'stored',
		'delete_pending',
		'deleted',
		'failed'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
	CREATE TYPE public.resource_visibility AS ENUM (
		'private',
		'restricted',
		'public'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
	CREATE TYPE public.resource_rights_status AS ENUM (
		'pending',
		'own-work',
		'authorized',
		'institutional',
		'bibliographic-reference-only',
		'copyright-restricted'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS public.academic_resources (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	owner_user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE RESTRICT,
	course_id text NOT NULL,
	academic_term_id text NULL,
	resource_type text NOT NULL,
	title text NOT NULL,
	description text NOT NULL,
	language text NOT NULL DEFAULT 'es',
	has_solution boolean NOT NULL DEFAULT false,
	tags text[] NOT NULL DEFAULT '{}'::text[],
	visibility public.resource_visibility NOT NULL DEFAULT 'private',
	review_status public.resource_review_status NOT NULL DEFAULT 'draft',
	rights_status public.resource_rights_status NOT NULL DEFAULT 'pending',
	rights_notes text NULL,
	submitted_at timestamptz NULL,
	reviewed_by uuid NULL REFERENCES public.profiles(user_id) ON DELETE SET NULL,
	reviewed_at timestamptz NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT academic_resources_course_id_not_empty_check CHECK (btrim(course_id) <> ''),
	CONSTRAINT academic_resources_academic_term_id_shape_check CHECK (
		academic_term_id IS NULL OR academic_term_id ~ '^[0-9]{4}-(1|2)$'
	),
	CONSTRAINT academic_resources_resource_type_check CHECK (
		resource_type IN (
			'syllabus',
			'exam',
			'solution',
			'notes',
			'assignment',
			'laboratory',
			'class-material',
			'book-reference'
		)
	),
	CONSTRAINT academic_resources_title_not_empty_check CHECK (btrim(title) <> ''),
	CONSTRAINT academic_resources_description_not_empty_check CHECK (btrim(description) <> ''),
	CONSTRAINT academic_resources_language_shape_check CHECK (language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
	CONSTRAINT academic_resources_tags_not_null_check CHECK (tags IS NOT NULL),
	CONSTRAINT academic_resources_draft_review_fields_check CHECK (
		review_status <> 'draft'::public.resource_review_status
		OR (submitted_at IS NULL AND reviewed_by IS NULL AND reviewed_at IS NULL)
	),
	CONSTRAINT academic_resources_pending_review_fields_check CHECK (
		review_status <> 'pending'::public.resource_review_status
		OR (submitted_at IS NOT NULL AND reviewed_by IS NULL AND reviewed_at IS NULL)
	),
	CONSTRAINT academic_resources_terminal_review_fields_check CHECK (
		review_status NOT IN (
			'approved'::public.resource_review_status,
			'rejected'::public.resource_review_status
		)
		OR (submitted_at IS NOT NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
	)
);

CREATE INDEX IF NOT EXISTS academic_resources_owner_status_idx
ON public.academic_resources (owner_user_id, review_status);

CREATE INDEX IF NOT EXISTS academic_resources_course_review_visibility_idx
ON public.academic_resources (course_id, review_status, visibility);

CREATE INDEX IF NOT EXISTS academic_resources_review_submitted_idx
ON public.academic_resources (review_status, submitted_at DESC);

CREATE INDEX IF NOT EXISTS academic_resources_rights_status_idx
ON public.academic_resources (rights_status);

CREATE TABLE IF NOT EXISTS public.resource_files (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	resource_id uuid NOT NULL REFERENCES public.academic_resources(id) ON DELETE CASCADE,
	uploaded_by uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE RESTRICT,
	display_filename text NOT NULL,
	content_type text NOT NULL,
	byte_size bigint NOT NULL,
	sha256 text NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT resource_files_display_filename_not_empty_check CHECK (btrim(display_filename) <> ''),
	CONSTRAINT resource_files_content_type_shape_check CHECK (content_type ~ '^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$'),
	CONSTRAINT resource_files_byte_size_positive_check CHECK (byte_size > 0),
	CONSTRAINT resource_files_sha256_shape_check CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$')
);

CREATE INDEX IF NOT EXISTS resource_files_resource_id_idx
ON public.resource_files (resource_id);

CREATE INDEX IF NOT EXISTS resource_files_uploaded_by_idx
ON public.resource_files (uploaded_by);

CREATE TABLE IF NOT EXISTS private.resource_storage_objects (
	file_id uuid PRIMARY KEY REFERENCES public.resource_files(id) ON DELETE CASCADE,
	storage_key text NOT NULL UNIQUE,
	storage_status public.resource_storage_status NOT NULL DEFAULT 'uploading',
	failure_reason text NULL,
	stored_at timestamptz NULL,
	delete_requested_at timestamptz NULL,
	deleted_at timestamptz NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT resource_storage_objects_storage_key_not_empty_check CHECK (btrim(storage_key) <> ''),
	CONSTRAINT resource_storage_objects_storage_key_private_shape_check CHECK (
		storage_key !~ '(^/|(^|/)\.\.(/|$)|\\|://)'
	),
	CONSTRAINT resource_storage_objects_stored_at_check CHECK (
		storage_status <> 'stored'::public.resource_storage_status OR stored_at IS NOT NULL
	),
	CONSTRAINT resource_storage_objects_deleted_at_check CHECK (
		storage_status <> 'deleted'::public.resource_storage_status OR deleted_at IS NOT NULL
	)
);

CREATE INDEX IF NOT EXISTS resource_storage_objects_status_idx
ON private.resource_storage_objects (storage_status);

CREATE INDEX IF NOT EXISTS resource_storage_objects_stored_at_idx
ON private.resource_storage_objects (stored_at DESC)
WHERE storage_status = 'stored'::public.resource_storage_status;

CREATE TABLE IF NOT EXISTS public.resource_review_events (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	resource_id uuid NOT NULL REFERENCES public.academic_resources(id) ON DELETE CASCADE,
	actor_user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE RESTRICT,
	from_status public.resource_review_status NULL,
	to_status public.resource_review_status NOT NULL,
	action text NOT NULL,
	comment text NULL,
	metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
	occurred_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT resource_review_events_action_check CHECK (
		action IN ('submit', 'approve', 'reject', 'storage_stored', 'storage_failed')
	),
	CONSTRAINT resource_review_events_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS resource_review_events_resource_occurred_idx
ON public.resource_review_events (resource_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS resource_review_events_actor_occurred_idx
ON public.resource_review_events (actor_user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS resource_review_events_action_idx
ON public.resource_review_events (action);

CREATE OR REPLACE FUNCTION private.is_active_user(requested_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT requested_user_id IS NOT NULL
		AND EXISTS (
			SELECT 1
			FROM public.profiles AS profile
			WHERE profile.user_id = requested_user_id
				AND profile.account_status = 'active'::public.account_status
		);
$$;

CREATE OR REPLACE FUNCTION private.can_create_academic_resource(
	resource_owner_user_id uuid,
	resource_review_status public.resource_review_status
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT auth.uid() IS NOT NULL
		AND resource_owner_user_id = auth.uid()
		AND resource_review_status = 'draft'::public.resource_review_status
		AND private.has_any_role(
			ARRAY[
				'contributor',
				'reviewer',
				'moderator',
				'administrator'
			]::public.app_role[]
		);
$$;

CREATE OR REPLACE FUNCTION private.can_edit_academic_resource(
	resource_owner_user_id uuid,
	resource_review_status public.resource_review_status
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT auth.uid() IS NOT NULL
		AND resource_owner_user_id = auth.uid()
		AND resource_review_status IN (
			'draft'::public.resource_review_status,
			'rejected'::public.resource_review_status
		)
		AND private.has_any_role(
			ARRAY[
				'contributor',
				'reviewer',
				'moderator',
				'administrator'
			]::public.app_role[]
		);
$$;

CREATE OR REPLACE FUNCTION private.can_review_resource()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT private.has_any_role(
		ARRAY[
			'reviewer',
			'moderator',
			'administrator'
		]::public.app_role[]
	);
$$;

CREATE OR REPLACE FUNCTION private.can_publish_resource()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT private.has_any_role(
		ARRAY[
			'moderator',
			'administrator'
		]::public.app_role[]
	);
$$;

CREATE OR REPLACE FUNCTION private.can_read_academic_resource(
	resource_owner_user_id uuid,
	resource_review_status public.resource_review_status,
	resource_visibility public.resource_visibility
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	current_user_id uuid := auth.uid();
BEGIN
	IF resource_review_status = 'approved'::public.resource_review_status
		AND resource_visibility = 'public'::public.resource_visibility THEN
		IF current_user_id IS NULL THEN
			RETURN true;
		END IF;

		RETURN private.is_active_user(current_user_id);
	END IF;

	IF current_user_id IS NULL OR NOT private.is_active_user(current_user_id) THEN
		RETURN false;
	END IF;

	IF private.has_any_role(ARRAY['moderator', 'administrator']::public.app_role[]) THEN
		RETURN true;
	END IF;

	IF resource_review_status = 'approved'::public.resource_review_status
		AND resource_visibility = 'restricted'::public.resource_visibility THEN
		RETURN true;
	END IF;

	IF resource_owner_user_id = current_user_id
		AND private.has_any_role(
			ARRAY[
				'contributor',
				'reviewer',
				'moderator',
				'administrator'
			]::public.app_role[]
		) THEN
		RETURN true;
	END IF;

	IF resource_review_status = 'pending'::public.resource_review_status
		AND private.has_any_role(ARRAY['reviewer', 'moderator', 'administrator']::public.app_role[]) THEN
		RETURN true;
	END IF;

	RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION private.can_read_resource_by_id(requested_resource_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	resource_record public.academic_resources%ROWTYPE;
BEGIN
	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = requested_resource_id;

	IF NOT FOUND THEN
		RETURN false;
	END IF;

	RETURN private.can_read_academic_resource(
		resource_record.owner_user_id,
		resource_record.review_status,
		resource_record.visibility
	);
END;
$$;

CREATE OR REPLACE FUNCTION private.resource_has_stored_files(requested_resource_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT EXISTS (
		SELECT 1
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id = requested_resource_id
			AND storage_object.storage_status = 'stored'::public.resource_storage_status
	);
$$;

CREATE OR REPLACE FUNCTION private.resource_has_unstored_files(requested_resource_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT EXISTS (
		SELECT 1
		FROM public.resource_files AS resource_file
		INNER JOIN private.resource_storage_objects AS storage_object
			ON storage_object.file_id = resource_file.id
		WHERE resource_file.resource_id = requested_resource_id
			AND storage_object.storage_status <> 'stored'::public.resource_storage_status
	);
$$;

CREATE OR REPLACE FUNCTION private.resource_rights_allow_stored_files(
	resource_rights_status public.resource_rights_status
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT resource_rights_status IN (
		'own-work'::public.resource_rights_status,
		'authorized'::public.resource_rights_status,
		'institutional'::public.resource_rights_status
	);
$$;

CREATE OR REPLACE FUNCTION private.resource_rights_block_approval(
	resource_rights_status public.resource_rights_status,
	has_stored_files boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT resource_rights_status = 'copyright-restricted'::public.resource_rights_status
		OR resource_rights_status = 'pending'::public.resource_rights_status
		OR (
			has_stored_files
			AND NOT private.resource_rights_allow_stored_files(resource_rights_status)
		);
$$;

CREATE OR REPLACE FUNCTION private.can_register_resource_file(requested_resource_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	resource_record public.academic_resources%ROWTYPE;
BEGIN
	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = requested_resource_id;

	IF NOT FOUND THEN
		RETURN false;
	END IF;

	RETURN private.can_edit_academic_resource(
		resource_record.owner_user_id,
		resource_record.review_status
	)
	AND resource_record.rights_status NOT IN (
		'bibliographic-reference-only'::public.resource_rights_status,
		'copyright-restricted'::public.resource_rights_status
	);
END;
$$;

CREATE OR REPLACE FUNCTION private.set_academic_resource_defaults_and_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	transition_context text := current_setting('app.resource_review_transition', true);
BEGIN
	IF TG_OP = 'INSERT' THEN
		NEW.created_at := COALESCE(NEW.created_at, now());
		NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
		NEW.tags := COALESCE(NEW.tags, '{}'::text[]);

		IF NEW.review_status <> 'draft'::public.resource_review_status
			AND transition_context IS DISTINCT FROM 'on' THEN
			RAISE EXCEPTION 'resource review status transitions must use RPC' USING ERRCODE = '42501';
		END IF;
	END IF;

	IF TG_OP = 'UPDATE' THEN
		IF NEW.id IS DISTINCT FROM OLD.id OR NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
			RAISE EXCEPTION 'resource identity fields are immutable' USING ERRCODE = '42501';
		END IF;

		NEW.created_at := OLD.created_at;
		NEW.updated_at := now();
		NEW.tags := COALESCE(NEW.tags, '{}'::text[]);

		IF (
			NEW.review_status IS DISTINCT FROM OLD.review_status
			OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
			OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
			OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
		) AND transition_context IS DISTINCT FROM 'on' THEN
			RAISE EXCEPTION 'resource review status transitions must use RPC' USING ERRCODE = '42501';
		END IF;
	END IF;

	IF NEW.review_status = 'draft'::public.resource_review_status
		AND (NEW.submitted_at IS NOT NULL OR NEW.reviewed_by IS NOT NULL OR NEW.reviewed_at IS NOT NULL) THEN
		RAISE EXCEPTION 'draft resources cannot carry review timestamps' USING ERRCODE = '23514';
	END IF;

	IF NEW.review_status = 'pending'::public.resource_review_status
		AND (NEW.submitted_at IS NULL OR NEW.reviewed_by IS NOT NULL OR NEW.reviewed_at IS NOT NULL) THEN
		RAISE EXCEPTION 'pending resources require only submitted_at' USING ERRCODE = '23514';
	END IF;

	IF NEW.review_status IN (
		'approved'::public.resource_review_status,
		'rejected'::public.resource_review_status
	) AND (NEW.submitted_at IS NULL OR NEW.reviewed_by IS NULL OR NEW.reviewed_at IS NULL) THEN
		RAISE EXCEPTION 'reviewed resources require review metadata' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_academic_resource_defaults_and_validate ON public.academic_resources;
CREATE TRIGGER set_academic_resource_defaults_and_validate
BEFORE INSERT OR UPDATE ON public.academic_resources
FOR EACH ROW
EXECUTE FUNCTION private.set_academic_resource_defaults_and_validate();

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
			OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by THEN
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

DROP TRIGGER IF EXISTS set_resource_file_defaults_and_validate ON public.resource_files;
CREATE TRIGGER set_resource_file_defaults_and_validate
BEFORE INSERT OR UPDATE ON public.resource_files
FOR EACH ROW
EXECUTE FUNCTION private.set_resource_file_defaults_and_validate();

CREATE OR REPLACE FUNCTION private.set_resource_storage_object_defaults_and_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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

	IF NEW.storage_status = 'stored'::public.resource_storage_status AND NEW.stored_at IS NULL THEN
		RAISE EXCEPTION 'stored resource objects require stored_at' USING ERRCODE = '23514';
	END IF;

	IF NEW.storage_status = 'deleted'::public.resource_storage_status AND NEW.deleted_at IS NULL THEN
		RAISE EXCEPTION 'deleted resource objects require deleted_at' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_resource_storage_object_defaults_and_validate ON private.resource_storage_objects;
CREATE TRIGGER set_resource_storage_object_defaults_and_validate
BEFORE INSERT OR UPDATE ON private.resource_storage_objects
FOR EACH ROW
EXECUTE FUNCTION private.set_resource_storage_object_defaults_and_validate();

CREATE OR REPLACE FUNCTION private.prevent_resource_review_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	RAISE EXCEPTION 'resource_review_events is append-only' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS prevent_resource_review_event_update ON public.resource_review_events;
CREATE TRIGGER prevent_resource_review_event_update
BEFORE UPDATE OR DELETE ON public.resource_review_events
FOR EACH ROW
EXECUTE FUNCTION private.prevent_resource_review_event_mutation();

CREATE OR REPLACE FUNCTION public.submit_academic_resource(
	resource_id uuid,
	comment text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	resource_record public.academic_resources%ROWTYPE;
	new_event_id bigint;
	normalized_comment text := NULLIF(btrim(comment), '');
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF NOT private.can_edit_academic_resource(resource_record.owner_user_id, resource_record.review_status) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	IF private.resource_has_unstored_files(resource_record.id) THEN
		RAISE EXCEPTION 'resource has incomplete file storage' USING ERRCODE = '23514';
	END IF;

	PERFORM set_config('app.resource_review_transition', 'on', true);

	UPDATE public.academic_resources
	SET review_status = 'pending'::public.resource_review_status,
		submitted_at = now(),
		reviewed_by = NULL,
		reviewed_at = NULL
	WHERE id = resource_record.id;

	PERFORM set_config('app.resource_review_transition', '', true);

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
		'pending'::public.resource_review_status,
		'submit',
		normalized_comment,
		'{}'::jsonb
	)
	RETURNING id INTO new_event_id;

	RETURN new_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_academic_resource(
	resource_id uuid,
	comment text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	resource_record public.academic_resources%ROWTYPE;
	new_event_id bigint;
	normalized_comment text := NULLIF(btrim(comment), '');
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_review_resource() THEN
		RAISE EXCEPTION 'reviewer role required' USING ERRCODE = '42501';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF resource_record.review_status <> 'pending'::public.resource_review_status THEN
		RAISE EXCEPTION 'only pending resources can be rejected' USING ERRCODE = '23514';
	END IF;

	PERFORM set_config('app.resource_review_transition', 'on', true);

	UPDATE public.academic_resources
	SET review_status = 'rejected'::public.resource_review_status,
		reviewed_by = actor_user_id,
		reviewed_at = now()
	WHERE id = resource_record.id;

	PERFORM set_config('app.resource_review_transition', '', true);

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
		'rejected'::public.resource_review_status,
		'reject',
		normalized_comment,
		'{}'::jsonb
	)
	RETURNING id INTO new_event_id;

	RETURN new_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_academic_resource(
	resource_id uuid,
	comment text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	resource_record public.academic_resources%ROWTYPE;
	new_event_id bigint;
	normalized_comment text := NULLIF(btrim(comment), '');
	has_stored_files boolean;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_publish_resource() THEN
		RAISE EXCEPTION 'moderator role required' USING ERRCODE = '42501';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = resource_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource does not exist' USING ERRCODE = 'P0002';
	END IF;

	IF resource_record.review_status <> 'pending'::public.resource_review_status THEN
		RAISE EXCEPTION 'only pending resources can be approved' USING ERRCODE = '23514';
	END IF;

	IF resource_record.visibility = 'private'::public.resource_visibility THEN
		RAISE EXCEPTION 'approved resources must be public or restricted' USING ERRCODE = '23514';
	END IF;

	IF private.resource_has_unstored_files(resource_record.id) THEN
		RAISE EXCEPTION 'resource has incomplete file storage' USING ERRCODE = '23514';
	END IF;

	has_stored_files := private.resource_has_stored_files(resource_record.id);

	IF private.resource_rights_block_approval(resource_record.rights_status, has_stored_files) THEN
		RAISE EXCEPTION 'resource rights do not allow approval' USING ERRCODE = '23514';
	END IF;

	PERFORM set_config('app.resource_review_transition', 'on', true);

	UPDATE public.academic_resources
	SET review_status = 'approved'::public.resource_review_status,
		reviewed_by = actor_user_id,
		reviewed_at = now()
	WHERE id = resource_record.id;

	PERFORM set_config('app.resource_review_transition', '', true);

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
		'approved'::public.resource_review_status,
		'approve',
		normalized_comment,
		jsonb_build_object('has_stored_files', has_stored_files)
	)
	RETURNING id INTO new_event_id;

	RETURN new_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_resource_file_upload(
	resource_id uuid,
	display_filename text,
	content_type text,
	byte_size bigint,
	sha256 text,
	storage_key text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	new_file_id uuid;
	normalized_display_filename text := NULLIF(btrim(display_filename), '');
	normalized_content_type text := lower(NULLIF(btrim(content_type), ''));
	normalized_sha256 text := lower(NULLIF(btrim(sha256), ''));
	normalized_storage_key text := NULLIF(btrim(storage_key), '');
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_register_resource_file(resource_id) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	IF normalized_display_filename IS NULL
		OR normalized_content_type IS NULL
		OR normalized_storage_key IS NULL
		OR byte_size IS NULL
		OR byte_size <= 0 THEN
		RAISE EXCEPTION 'valid file metadata is required' USING ERRCODE = '23514';
	END IF;

	IF normalized_storage_key ~ '(^/|(^|/)\.\.(/|$)|\\|://)' THEN
		RAISE EXCEPTION 'storage key must be a private relative key' USING ERRCODE = '23514';
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
		resource_id,
		actor_user_id,
		normalized_display_filename,
		normalized_content_type,
		byte_size,
		normalized_sha256
	)
	RETURNING id INTO new_file_id;

	INSERT INTO private.resource_storage_objects (
		file_id,
		storage_key,
		storage_status
	)
	VALUES (
		new_file_id,
		normalized_storage_key,
		'uploading'::public.resource_storage_status
	);

	RETURN new_file_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_resource_file_stored(
	file_id uuid,
	sha256 text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	file_record public.resource_files%ROWTYPE;
	resource_record public.academic_resources%ROWTYPE;
	normalized_sha256 text := lower(NULLIF(btrim(sha256), ''));
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	SELECT *
	INTO file_record
	FROM public.resource_files
	WHERE id = file_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = file_record.resource_id
	FOR UPDATE;

	IF NOT private.can_edit_academic_resource(resource_record.owner_user_id, resource_record.review_status) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	IF resource_record.rights_status IN (
		'bibliographic-reference-only'::public.resource_rights_status,
		'copyright-restricted'::public.resource_rights_status
	) THEN
		RAISE EXCEPTION 'resource rights do not allow stored files' USING ERRCODE = '23514';
	END IF;

	IF NOT EXISTS (
		SELECT 1
		FROM private.resource_storage_objects AS storage_object
		WHERE storage_object.file_id = file_record.id
			AND storage_object.storage_status = 'uploading'::public.resource_storage_status
		FOR UPDATE
	) THEN
		RAISE EXCEPTION 'resource file is not awaiting storage' USING ERRCODE = '23514';
	END IF;

	UPDATE public.resource_files
	SET sha256 = COALESCE(normalized_sha256, public.resource_files.sha256)
	WHERE public.resource_files.id = file_record.id;

	UPDATE private.resource_storage_objects
	SET storage_status = 'stored'::public.resource_storage_status,
		stored_at = now(),
		failure_reason = NULL
	WHERE private.resource_storage_objects.file_id = file_record.id;

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
		'storage_stored',
		NULL,
		jsonb_build_object('file_id', file_record.id)
	);

	RETURN file_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_resource_file_failed(
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
	file_record public.resource_files%ROWTYPE;
	resource_record public.academic_resources%ROWTYPE;
	normalized_reason text := NULLIF(btrim(reason), '');
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	SELECT *
	INTO file_record
	FROM public.resource_files
	WHERE id = file_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file does not exist' USING ERRCODE = 'P0002';
	END IF;

	SELECT *
	INTO resource_record
	FROM public.academic_resources
	WHERE id = file_record.resource_id
	FOR UPDATE;

	IF NOT private.can_edit_academic_resource(resource_record.owner_user_id, resource_record.review_status) THEN
		RAISE EXCEPTION 'resource owner contributor role required' USING ERRCODE = '42501';
	END IF;

	UPDATE private.resource_storage_objects
	SET storage_status = 'failed'::public.resource_storage_status,
		failure_reason = normalized_reason
	WHERE private.resource_storage_objects.file_id = file_record.id
		AND private.resource_storage_objects.storage_status = 'uploading'::public.resource_storage_status;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'resource file is not awaiting storage' USING ERRCODE = '23514';
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
		'storage_failed',
		normalized_reason,
		jsonb_build_object('file_id', file_record.id)
	);

	RETURN file_record.id;
END;
$$;

ALTER TABLE public.academic_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.resource_storage_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_review_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS academic_resources_select_public_approved ON public.academic_resources;
CREATE POLICY academic_resources_select_public_approved
ON public.academic_resources
FOR SELECT
TO anon
USING (
	review_status = 'approved'::public.resource_review_status
	AND visibility = 'public'::public.resource_visibility
);

DROP POLICY IF EXISTS academic_resources_select_authenticated ON public.academic_resources;
CREATE POLICY academic_resources_select_authenticated
ON public.academic_resources
FOR SELECT
TO authenticated
USING ((SELECT private.can_read_academic_resource(owner_user_id, review_status, visibility)));

DROP POLICY IF EXISTS academic_resources_insert_contributor_own_draft ON public.academic_resources;
CREATE POLICY academic_resources_insert_contributor_own_draft
ON public.academic_resources
FOR INSERT
TO authenticated
WITH CHECK ((SELECT private.can_create_academic_resource(owner_user_id, review_status)));

DROP POLICY IF EXISTS academic_resources_update_contributor_own_draft_rejected ON public.academic_resources;
CREATE POLICY academic_resources_update_contributor_own_draft_rejected
ON public.academic_resources
FOR UPDATE
TO authenticated
USING ((SELECT private.can_edit_academic_resource(owner_user_id, review_status)))
WITH CHECK ((SELECT private.can_edit_academic_resource(owner_user_id, review_status)));

DROP POLICY IF EXISTS resource_files_select_public_readable ON public.resource_files;
CREATE POLICY resource_files_select_public_readable
ON public.resource_files
FOR SELECT
TO anon
USING ((SELECT private.can_read_resource_by_id(resource_id)));

DROP POLICY IF EXISTS resource_files_select_authenticated_readable ON public.resource_files;
CREATE POLICY resource_files_select_authenticated_readable
ON public.resource_files
FOR SELECT
TO authenticated
USING ((SELECT private.can_read_resource_by_id(resource_id)));

DROP POLICY IF EXISTS resource_review_events_select_authenticated_readable ON public.resource_review_events;
CREATE POLICY resource_review_events_select_authenticated_readable
ON public.resource_review_events
FOR SELECT
TO authenticated
USING ((SELECT private.can_read_resource_by_id(resource_id)));

REVOKE ALL ON TABLE public.academic_resources FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.resource_files FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE private.resource_storage_objects FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.resource_review_events FROM PUBLIC, anon, authenticated;

REVOKE ALL ON SEQUENCE public.resource_review_events_id_seq FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TYPE public.resource_review_status FROM PUBLIC;
REVOKE ALL ON TYPE public.resource_storage_status FROM PUBLIC;
REVOKE ALL ON TYPE public.resource_visibility FROM PUBLIC;
REVOKE ALL ON TYPE public.resource_rights_status FROM PUBLIC;

GRANT USAGE ON TYPE public.resource_review_status TO anon, authenticated;
GRANT USAGE ON TYPE public.resource_visibility TO anon, authenticated;
GRANT USAGE ON TYPE public.resource_rights_status TO anon, authenticated;

GRANT SELECT ON TABLE public.academic_resources TO anon, authenticated;
GRANT INSERT ON TABLE public.academic_resources TO authenticated;
GRANT UPDATE (
	course_id,
	academic_term_id,
	resource_type,
	title,
	description,
	language,
	has_solution,
	tags,
	visibility,
	rights_status,
	rights_notes
) ON TABLE public.academic_resources TO authenticated;
GRANT SELECT ON TABLE public.resource_files TO anon, authenticated;
GRANT SELECT ON TABLE public.resource_review_events TO authenticated;

REVOKE ALL ON FUNCTION private.is_active_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_create_academic_resource(uuid, public.resource_review_status) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_edit_academic_resource(uuid, public.resource_review_status) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_review_resource() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_publish_resource() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_read_academic_resource(uuid, public.resource_review_status, public.resource_visibility) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_read_resource_by_id(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.resource_has_stored_files(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.resource_has_unstored_files(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.resource_rights_allow_stored_files(public.resource_rights_status) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.resource_rights_block_approval(public.resource_rights_status, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_register_resource_file(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.set_academic_resource_defaults_and_validate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.set_resource_file_defaults_and_validate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.set_resource_storage_object_defaults_and_validate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.prevent_resource_review_event_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_academic_resource(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reject_academic_resource(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_academic_resource(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.register_resource_file_upload(uuid, text, text, bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_resource_file_stored(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_resource_file_failed(uuid, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION private.can_create_academic_resource(uuid, public.resource_review_status) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_edit_academic_resource(uuid, public.resource_review_status) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_academic_resource(uuid, public.resource_review_status, public.resource_visibility) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_resource_by_id(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_academic_resource(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_academic_resource(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_academic_resource(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_resource_file_upload(uuid, text, text, bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_resource_file_stored(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_resource_file_failed(uuid, text) TO authenticated;

COMMIT;
