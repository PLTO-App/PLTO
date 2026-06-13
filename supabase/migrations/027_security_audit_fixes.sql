-- ============================================================
-- Security Audit Fixes (2026-06-13)
-- ============================================================
-- Issues addressed:
--   1. Revoke anon FULL access from views (overdue_tasks, pipeline_summary, liders_invoices)
--   2. Revoke anon EXECUTE on SECURITY DEFINER helper functions
--   3. Fix agent_users RLS policy: add tenant_access_active() check
--   4. Fix admin function plan validation (align with tenants CHECK constraint)
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Revoke anon grants on views that should be authenticated-only
-- ----------------------------------------------------------------

REVOKE ALL ON public.overdue_tasks    FROM anon;
REVOKE ALL ON public.pipeline_summary FROM anon;

-- liders_invoices is service_role-only via RLS, anon grant is unnecessary
REVOKE ALL ON public.liders_invoices  FROM anon;


-- ----------------------------------------------------------------
-- 2. Revoke anon EXECUTE on SECURITY DEFINER helper functions
--    (Supabase advisor lint: anon_security_definer_function_executable)
--    For anon, auth.uid() = NULL so these return NULL anyway,
--    but removing EXECUTE eliminates the exposure entirely.
-- ----------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.get_my_tenant_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_agent_id()  FROM anon;


-- ----------------------------------------------------------------
-- 3. Fix agent_users RLS policy — add tenant_access_active() check
--    All other tables already include this; agent_users was missing it,
--    allowing expired/cancelled tenants to still read/write agent rows.
-- ----------------------------------------------------------------

DROP POLICY IF EXISTS "agents in same tenant" ON public.agent_users;

CREATE POLICY "agents in same tenant"
  ON public.agent_users
  AS PERMISSIVE
  FOR ALL
  TO public
  USING (
    tenant_id = get_my_tenant_id()
    AND tenant_access_active()
  )
  WITH CHECK (
    tenant_id = get_my_tenant_id()
    AND tenant_access_active()
  );


-- ----------------------------------------------------------------
-- 4a. Fix admin_set_plan — align allowed plans with tenants CHECK constraint
--     Old: allowed 'cancelled' which is NOT in the DB constraint
--     New: allows all valid plans ('trial','basic','pro','premium','internal','lifetime')
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_set_plan(
  p_tenant_id       uuid,
  p_plan            text,
  p_trial_ends_at   timestamp with time zone DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller text := auth.email();
BEGIN
  IF v_caller NOT IN ('liders.crm@gmail.com', 'elgrablidudu@gmail.com') THEN
    RAISE EXCEPTION 'admin access required';
  END IF;
  IF p_plan NOT IN ('trial', 'basic', 'pro', 'premium', 'internal', 'lifetime') THEN
    RAISE EXCEPTION 'invalid plan: %', p_plan;
  END IF;
  UPDATE tenants
    SET plan            = p_plan,
        trial_ends_at   = p_trial_ends_at
  WHERE id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant not found';
  END IF;
END;
$$;

-- Restore grants after CREATE OR REPLACE
GRANT EXECUTE ON FUNCTION public.admin_set_plan(uuid, text, timestamp with time zone)
  TO authenticated, service_role;


-- ----------------------------------------------------------------
-- 4b. Fix admin_save_account — align allowed plans with tenants CHECK constraint
--     Old: allowed 'trial','basic','pro','premium' only
--     New: also allows 'internal','lifetime'
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_save_account(
  p_id    uuid,
  p_name  text,
  p_email text,
  p_plan  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller text := auth.email();
  v_slug   text;
BEGIN
  IF v_caller NOT IN ('liders.crm@gmail.com', 'elgrablidudu@gmail.com') THEN
    RAISE EXCEPTION 'admin access required';
  END IF;
  IF trim(coalesce(p_name, '')) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;
  IF p_plan NOT IN ('trial', 'basic', 'pro', 'premium', 'internal', 'lifetime') THEN
    RAISE EXCEPTION 'invalid plan: %', p_plan;
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE tenants
      SET name          = trim(p_name),
          billing_email = nullif(trim(coalesce(p_email, '')), ''),
          plan          = p_plan
    WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'tenant not found';
    END IF;
  ELSE
    v_slug := 'agency-' || substr(md5(random()::text || clock_timestamp()::text), 1, 8);
    INSERT INTO tenants (name, billing_email, plan, slug, trial_ends_at)
    VALUES (
      trim(p_name),
      nullif(trim(coalesce(p_email, '')), ''),
      p_plan,
      v_slug,
      CASE WHEN p_plan = 'trial' THEN now() + interval '21 days' ELSE NULL END
    );
  END IF;
END;
$$;

-- Restore grants after CREATE OR REPLACE
GRANT EXECUTE ON FUNCTION public.admin_save_account(uuid, text, text, text)
  TO authenticated, service_role;
