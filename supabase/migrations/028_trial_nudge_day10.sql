-- Liders CRM — Migration 028: Add mid-trial nudge (day 10 remaining)
-- Extends get_trial_expiry_candidates() to also return day-10 "midway" tenants
-- so Make.com can send a friendly check-in nudge email.

CREATE OR REPLACE FUNCTION public.get_trial_expiry_candidates()
RETURNS TABLE (
  tenant_id         uuid,
  tenant_name       text,
  billing_email     text,
  trial_ends_at     timestamptz,
  days_remaining    int,
  notification_type text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    t.id                                                          AS tenant_id,
    t.name                                                        AS tenant_name,
    t.billing_email,
    t.trial_ends_at,
    FLOOR(EXTRACT(EPOCH FROM (t.trial_ends_at - now())) / 86400)::int AS days_remaining,
    CASE FLOOR(EXTRACT(EPOCH FROM (t.trial_ends_at - now())) / 86400)::int
      WHEN 10 THEN 'midtrial_nudge'
      WHEN  7 THEN '7_days'
      WHEN  3 THEN '3_days'
      WHEN  1 THEN '1_day'
      WHEN  0 THEN 'expired_today'
      WHEN -1 THEN 'delete_warning'
    END AS notification_type
  FROM tenants t
  WHERE
    t.plan           = 'trial'
    AND t.is_active  = true
    AND t.billing_email IS NOT NULL
    AND t.billing_email != 'demo@liders.co.il'
    AND t.trial_ends_at IS NOT NULL
    AND FLOOR(EXTRACT(EPOCH FROM (t.trial_ends_at - now())) / 86400)::int
        IN (10, 7, 3, 1, 0, -1)
$$;

REVOKE ALL  ON FUNCTION public.get_trial_expiry_candidates() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trial_expiry_candidates() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_trial_expiry_candidates() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.get_trial_expiry_candidates() TO service_role;
