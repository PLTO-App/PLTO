-- ══════════════════════════════════════════════════
--  Migration 002: Switch from PIN to Google Auth
--  Applied: 2026-06-10
-- ══════════════════════════════════════════════════

-- Replace anon leads policy with authenticated + email whitelist
DROP POLICY IF EXISTS anon_all_leads ON leads;

CREATE POLICY auth_admin_leads ON leads
  FOR ALL TO authenticated
  USING (auth.email() = ANY(ARRAY['liders.crm@gmail.com','elgrablidudu@gmail.com']))
  WITH CHECK (auth.email() = ANY(ARRAY['liders.crm@gmail.com','elgrablidudu@gmail.com']));

-- New save_crm_settings: auth.email() instead of PIN
CREATE OR REPLACE FUNCTION public.save_crm_settings(
  p_company_name text,
  p_tagline      text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.email() NOT IN ('liders.crm@gmail.com','elgrablidudu@gmail.com') THEN
    RETURN FALSE;
  END IF;
  UPDATE public.crm_settings
    SET company_name = p_company_name,
        tagline      = p_tagline
    WHERE id = 1;
  RETURN TRUE;
END;
$$;
