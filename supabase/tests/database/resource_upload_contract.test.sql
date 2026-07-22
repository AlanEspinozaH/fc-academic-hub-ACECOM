SET search_path TO public, extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

BEGIN;

SELECT no_plan();

-- Stage 4B.2 atomic upload contract tests.

SELECT * FROM finish();

ROLLBACK;
