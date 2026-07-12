-- Migration 081: Replace the admin-guard email liders.crm@gmail.com with
-- info@plto.app across every RPC that checks it, as an interim replacement
-- until a dedicated admin@plto.app mailbox is created. elgrablidudu@gmail.com
-- is untouched. Uses a dynamic loop over pg_get_functiondef() instead of
-- hand-editing 17 functions individually, to avoid transcription errors.

DO $migrate$
DECLARE
  r RECORD;
  v_def text;
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%liders.crm@gmail.com%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_def := replace(v_def, 'liders.crm@gmail.com', 'info@plto.app');
    EXECUTE v_def;
  END LOOP;
END;
$migrate$;
