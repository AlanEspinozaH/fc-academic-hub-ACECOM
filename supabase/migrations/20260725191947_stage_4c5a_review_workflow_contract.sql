BEGIN;

DROP FUNCTION IF EXISTS public.approve_academic_resource(uuid, text);

CREATE FUNCTION public.approve_academic_resource(
	resource_id uuid,
	final_visibility public.resource_visibility,
	comment text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_final_visibility public.resource_visibility := final_visibility;
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

	IF requested_final_visibility IS NULL
		OR requested_final_visibility NOT IN (
			'public'::public.resource_visibility,
			'restricted'::public.resource_visibility,
			'privileged'::public.resource_visibility
		) THEN
		RAISE EXCEPTION 'approval requires a final publication audience' USING ERRCODE = '23514';
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

	IF resource_record.owner_user_id = actor_user_id THEN
		RAISE EXCEPTION 'users cannot approve their own resources' USING ERRCODE = '42501';
	END IF;

	IF resource_record.rights_status = 'institutional'::public.resource_rights_status
		AND requested_final_visibility = 'public'::public.resource_visibility THEN
		RAISE EXCEPTION 'institutional rights do not allow public visibility' USING ERRCODE = '23514';
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
	SET visibility = requested_final_visibility,
		review_status = 'approved'::public.resource_review_status,
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
		jsonb_build_object(
			'has_stored_files', has_stored_files,
			'proposed_visibility', resource_record.visibility,
			'final_visibility', requested_final_visibility
		)
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

	IF normalized_comment IS NULL THEN
		RAISE EXCEPTION 'rejection comment is required' USING ERRCODE = '23514';
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

REVOKE ALL
ON FUNCTION public.approve_academic_resource(uuid, public.resource_visibility, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.approve_academic_resource(uuid, public.resource_visibility, text)
TO authenticated;

REVOKE ALL
ON FUNCTION public.reject_academic_resource(uuid, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.reject_academic_resource(uuid, text)
TO authenticated;

COMMIT;
