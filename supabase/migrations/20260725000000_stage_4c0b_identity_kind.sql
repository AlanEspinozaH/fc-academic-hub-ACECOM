BEGIN;

DO $$
BEGIN
	CREATE TYPE public.identity_kind AS ENUM (
		'institutional',
		'external_authorized'
	);
EXCEPTION
	WHEN duplicate_object THEN NULL;
END;
$$;

ALTER TABLE public.profiles
ADD COLUMN identity_kind public.identity_kind NOT NULL DEFAULT 'institutional';

REVOKE ALL ON TYPE public.identity_kind FROM PUBLIC;
GRANT USAGE ON TYPE public.identity_kind TO authenticated;

COMMIT;
