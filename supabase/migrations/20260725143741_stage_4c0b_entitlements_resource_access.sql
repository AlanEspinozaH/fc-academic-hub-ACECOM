BEGIN;

CREATE TYPE public.app_entitlement AS ENUM (
	'privileged_material.read'
);

CREATE TABLE public.user_entitlements (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	entitlement public.app_entitlement NOT NULL,
	granted_by uuid NOT NULL REFERENCES public.profiles(user_id),
	granted_at timestamptz NOT NULL DEFAULT now(),
	revoked_by uuid NULL REFERENCES public.profiles(user_id),
	revoked_at timestamptz NULL,
	reason text NULL,
	CONSTRAINT user_entitlements_revocation_pair_check CHECK (
		(revoked_by IS NULL AND revoked_at IS NULL)
		OR (revoked_by IS NOT NULL AND revoked_at IS NOT NULL)
	),
	CONSTRAINT user_entitlements_revoked_after_granted_check CHECK (
		revoked_at IS NULL OR revoked_at >= granted_at
	)
);

CREATE UNIQUE INDEX user_entitlements_one_active_assignment_idx
ON public.user_entitlements (user_id, entitlement)
WHERE revoked_at IS NULL;

CREATE INDEX user_entitlements_user_id_revoked_at_idx
ON public.user_entitlements (user_id, revoked_at);

CREATE INDEX user_entitlements_granted_by_idx
ON public.user_entitlements (granted_by);

CREATE INDEX user_entitlements_revoked_by_idx
ON public.user_entitlements (revoked_by)
WHERE revoked_by IS NOT NULL;

CREATE TABLE public.entitlement_audit_log (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	actor_user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	target_user_id uuid NOT NULL REFERENCES public.profiles(user_id),
	action text NOT NULL,
	entitlement public.app_entitlement NOT NULL,
	occurred_at timestamptz NOT NULL DEFAULT now(),
	metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
	CONSTRAINT entitlement_audit_log_action_check CHECK (action IN ('grant', 'revoke')),
	CONSTRAINT entitlement_audit_log_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX entitlement_audit_log_actor_occurred_at_idx
ON public.entitlement_audit_log (actor_user_id, occurred_at DESC);

CREATE INDEX entitlement_audit_log_target_occurred_at_idx
ON public.entitlement_audit_log (target_user_id, occurred_at DESC);

CREATE INDEX entitlement_audit_log_entitlement_action_idx
ON public.entitlement_audit_log (entitlement, action);

CREATE OR REPLACE FUNCTION private.prevent_entitlement_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
	RAISE EXCEPTION 'entitlement_audit_log is append-only' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER prevent_entitlement_audit_log_update
BEFORE UPDATE OR DELETE ON public.entitlement_audit_log
FOR EACH ROW
EXECUTE FUNCTION private.prevent_entitlement_audit_log_mutation();

CREATE OR REPLACE FUNCTION private.has_entitlement(
	requested_entitlement public.app_entitlement
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT auth.uid() IS NOT NULL
		AND EXISTS (
			SELECT 1
			FROM public.user_entitlements AS assigned_entitlement
			INNER JOIN public.profiles AS profile
				ON profile.user_id = assigned_entitlement.user_id
			WHERE assigned_entitlement.user_id = auth.uid()
				AND assigned_entitlement.entitlement = requested_entitlement
				AND assigned_entitlement.revoked_at IS NULL
				AND profile.account_status = 'active'::public.account_status
				AND profile.identity_kind IN (
					'institutional'::public.identity_kind,
					'external_authorized'::public.identity_kind
				)
		);
$$;

CREATE OR REPLACE FUNCTION private.can_manage_entitlements()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
	SELECT private.has_role('administrator'::public.app_role);
$$;

CREATE OR REPLACE FUNCTION public.grant_user_entitlement(
	target_user_id uuid,
	entitlement public.app_entitlement,
	reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_entitlement public.app_entitlement := entitlement;
	target_account_status public.account_status;
	target_identity_kind public.identity_kind;
	new_assignment_id bigint;
	normalized_reason text := NULLIF(btrim(reason), '');
	audit_metadata jsonb := '{}'::jsonb;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_manage_entitlements() THEN
		RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501';
	END IF;

	IF target_user_id IS NULL OR requested_entitlement IS NULL THEN
		RAISE EXCEPTION 'target user and entitlement are required' USING ERRCODE = '22004';
	END IF;

	IF actor_user_id = target_user_id THEN
		RAISE EXCEPTION 'users cannot grant entitlements to themselves' USING ERRCODE = '42501';
	END IF;

	SELECT profile.account_status, profile.identity_kind
	INTO target_account_status, target_identity_kind
	FROM public.profiles AS profile
	WHERE profile.user_id = target_user_id
	FOR UPDATE;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'target profile does not exist' USING ERRCODE = '23503';
	END IF;

	IF target_account_status <> 'active'::public.account_status
		OR target_identity_kind NOT IN (
			'institutional'::public.identity_kind,
			'external_authorized'::public.identity_kind
		) THEN
		RAISE EXCEPTION 'target profile is not eligible for entitlements' USING ERRCODE = '42501';
	END IF;

	IF EXISTS (
		SELECT 1
		FROM public.user_entitlements AS assigned_entitlement
		WHERE assigned_entitlement.user_id = target_user_id
			AND assigned_entitlement.entitlement = requested_entitlement
			AND assigned_entitlement.revoked_at IS NULL
	) THEN
		RAISE EXCEPTION 'active entitlement assignment already exists' USING ERRCODE = '23505';
	END IF;

	IF normalized_reason IS NOT NULL THEN
		audit_metadata := audit_metadata || jsonb_build_object('reason', normalized_reason);
	END IF;

	INSERT INTO public.user_entitlements (
		user_id,
		entitlement,
		granted_by,
		granted_at,
		reason
	)
	VALUES (
		target_user_id,
		requested_entitlement,
		actor_user_id,
		now(),
		normalized_reason
	)
	RETURNING id INTO new_assignment_id;

	INSERT INTO public.entitlement_audit_log (
		actor_user_id,
		target_user_id,
		action,
		entitlement,
		occurred_at,
		metadata
	)
	VALUES (
		actor_user_id,
		target_user_id,
		'grant',
		requested_entitlement,
		now(),
		audit_metadata || jsonb_build_object('assignment_id', new_assignment_id)
	);

	RETURN new_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_user_entitlement(
	target_user_id uuid,
	entitlement public.app_entitlement,
	reason text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
	actor_user_id uuid := auth.uid();
	requested_entitlement public.app_entitlement := entitlement;
	revoked_assignment_id bigint;
	normalized_reason text := NULLIF(btrim(reason), '');
	audit_metadata jsonb := '{}'::jsonb;
BEGIN
	IF actor_user_id IS NULL THEN
		RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
	END IF;

	IF NOT private.can_manage_entitlements() THEN
		RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501';
	END IF;

	IF target_user_id IS NULL OR requested_entitlement IS NULL THEN
		RAISE EXCEPTION 'target user and entitlement are required' USING ERRCODE = '22004';
	END IF;

	IF actor_user_id = target_user_id THEN
		RAISE EXCEPTION 'users cannot revoke entitlements from themselves' USING ERRCODE = '42501';
	END IF;

	IF normalized_reason IS NOT NULL THEN
		audit_metadata := audit_metadata || jsonb_build_object('reason', normalized_reason);
	END IF;

	UPDATE public.user_entitlements AS assigned_entitlement
	SET revoked_by = actor_user_id,
		revoked_at = now()
	WHERE assigned_entitlement.user_id = target_user_id
		AND assigned_entitlement.entitlement = requested_entitlement
		AND assigned_entitlement.revoked_at IS NULL
	RETURNING assigned_entitlement.id INTO revoked_assignment_id;

	IF revoked_assignment_id IS NULL THEN
		RAISE EXCEPTION 'active entitlement assignment does not exist' USING ERRCODE = 'P0002';
	END IF;

	INSERT INTO public.entitlement_audit_log (
		actor_user_id,
		target_user_id,
		action,
		entitlement,
		occurred_at,
		metadata
	)
	VALUES (
		actor_user_id,
		target_user_id,
		'revoke',
		requested_entitlement,
		now(),
		audit_metadata || jsonb_build_object('assignment_id', revoked_assignment_id)
	);

	RETURN revoked_assignment_id;
END;
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
		'institutional'::public.resource_rights_status,
		'open-license'::public.resource_rights_status,
		'public-domain'::public.resource_rights_status
	);
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

	IF NEW.review_status = 'approved'::public.resource_review_status
		AND NEW.visibility = 'private'::public.resource_visibility THEN
		RAISE EXCEPTION 'approved resources require a final audience' USING ERRCODE = '23514';
	END IF;

	IF NEW.rights_status = 'institutional'::public.resource_rights_status
		AND NEW.visibility = 'public'::public.resource_visibility THEN
		RAISE EXCEPTION 'institutional rights do not allow public visibility' USING ERRCODE = '23514';
	END IF;

	RETURN NEW;
END;
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
	current_identity_kind public.identity_kind;
BEGIN
	IF resource_review_status = 'approved'::public.resource_review_status
		AND resource_visibility = 'public'::public.resource_visibility THEN
		RETURN true;
	END IF;

	IF current_user_id IS NULL OR NOT private.is_active_user(current_user_id) THEN
		RETURN false;
	END IF;

	IF private.has_role('administrator'::public.app_role) THEN
		RETURN true;
	END IF;

	IF resource_review_status = 'approved'::public.resource_review_status THEN
		IF private.has_role('moderator'::public.app_role) THEN
			RETURN true;
		END IF;

		IF resource_visibility = 'restricted'::public.resource_visibility THEN
			SELECT profile.identity_kind
			INTO current_identity_kind
			FROM public.profiles AS profile
			WHERE profile.user_id = current_user_id;

			RETURN current_identity_kind = 'institutional'::public.identity_kind;
		END IF;

		IF resource_visibility = 'privileged'::public.resource_visibility THEN
			RETURN private.has_entitlement(
				'privileged_material.read'::public.app_entitlement
			);
		END IF;

		RETURN false;
	END IF;

	IF resource_owner_user_id = current_user_id
		AND resource_review_status IN (
			'draft'::public.resource_review_status,
			'pending'::public.resource_review_status,
			'rejected'::public.resource_review_status
		)
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
		AND private.has_any_role(
			ARRAY[
				'reviewer',
				'moderator',
				'administrator'
			]::public.app_role[]
		) THEN
		RETURN true;
	END IF;

	RETURN false;
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

	IF resource_record.owner_user_id = actor_user_id THEN
		RAISE EXCEPTION 'users cannot approve their own resources' USING ERRCODE = '42501';
	END IF;

	IF resource_record.visibility = 'private'::public.resource_visibility THEN
		RAISE EXCEPTION 'approved resources require a final audience' USING ERRCODE = '23514';
	END IF;

	IF resource_record.rights_status = 'institutional'::public.resource_rights_status
		AND resource_record.visibility = 'public'::public.resource_visibility THEN
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

DROP POLICY IF EXISTS academic_resources_select_public_approved ON public.academic_resources;
CREATE POLICY academic_resources_select_public_approved
ON public.academic_resources
FOR SELECT
TO anon
USING ((SELECT private.can_read_resource_by_id(id)));

DROP POLICY IF EXISTS academic_resources_select_authenticated ON public.academic_resources;
CREATE POLICY academic_resources_select_authenticated
ON public.academic_resources
FOR SELECT
TO authenticated
USING ((SELECT private.can_read_resource_by_id(id)));

ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlement_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_entitlements_select_own_active_or_admin
ON public.user_entitlements
FOR SELECT
TO authenticated
USING (
	(user_id = (SELECT auth.uid()) AND revoked_at IS NULL)
	OR (SELECT private.has_role('administrator'::public.app_role))
);

CREATE POLICY entitlement_audit_log_select_admin
ON public.entitlement_audit_log
FOR SELECT
TO authenticated
USING ((SELECT private.has_role('administrator'::public.app_role)));

REVOKE ALL ON TABLE public.user_entitlements FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.entitlement_audit_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.user_entitlements_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.entitlement_audit_log_id_seq FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.user_entitlements TO authenticated;
GRANT SELECT ON TABLE public.entitlement_audit_log TO authenticated;

REVOKE ALL ON TYPE public.app_entitlement FROM PUBLIC;
GRANT USAGE ON TYPE public.app_entitlement TO authenticated;

REVOKE ALL ON FUNCTION private.prevent_entitlement_audit_log_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.has_entitlement(public.app_entitlement) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_manage_entitlements() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.grant_user_entitlement(uuid, public.app_entitlement, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_user_entitlement(uuid, public.app_entitlement, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.grant_user_entitlement(uuid, public.app_entitlement, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_user_entitlement(uuid, public.app_entitlement, text) TO authenticated;

COMMIT;
