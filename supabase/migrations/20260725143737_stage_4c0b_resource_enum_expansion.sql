BEGIN;

ALTER TYPE public.resource_visibility
ADD VALUE IF NOT EXISTS 'privileged';

ALTER TYPE public.resource_rights_status
ADD VALUE IF NOT EXISTS 'open-license';

ALTER TYPE public.resource_rights_status
ADD VALUE IF NOT EXISTS 'public-domain';

COMMIT;
