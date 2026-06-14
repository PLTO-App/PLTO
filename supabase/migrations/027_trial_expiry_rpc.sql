-- Migration 027: RPC לאוטומציית מיילי פג-תוקף ניסיון
-- מחזיר רשימת טנאנטים שצריכים לקבל מייל היום (מופעל מ-Make.com פעם ביום)

CREATE OR REPLACE FUNCTION public.get_trial_expiry_candidates()
RETURNS TABLE (
  tenant_id     uuid,
  tenant_name   text,
  billing_email text,
  days_left     int,
  email_type    text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  tz text := 'Asia/Jerusalem';
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.name,
    t.billing_email,
    GREATEST(0, CEIL(EXTRACT(EPOCH FROM (t.trial_ends_at - now())) / 86400))::int AS days_left,
    CASE
      WHEN date_trunc('day', t.trial_ends_at AT TIME ZONE tz) =
           date_trunc('day', (now() + interval '7 days') AT TIME ZONE tz)
        THEN 'seven_days_left'
      WHEN date_trunc('day', t.trial_ends_at AT TIME ZONE tz) =
           date_trunc('day', (now() + interval '3 days') AT TIME ZONE tz)
        THEN 'three_days_left'
      WHEN date_trunc('day', t.trial_ends_at AT TIME ZONE tz) =
           date_trunc('day', (now() + interval '1 day') AT TIME ZONE tz)
        THEN 'one_day_left'
      WHEN date_trunc('day', t.trial_ends_at AT TIME ZONE tz) =
           date_trunc('day', now() AT TIME ZONE tz)
        THEN 'expired_today'
      WHEN date_trunc('day', t.trial_ends_at AT TIME ZONE tz) =
           date_trunc('day', (now() - interval '29 days') AT TIME ZONE tz)
        THEN 'data_delete_tomorrow'
    END AS email_type
  FROM tenants t
  WHERE t.plan = 'trial'
    AND t.billing_email IS NOT NULL
    AND t.is_active = true
    AND date_trunc('day', t.trial_ends_at AT TIME ZONE tz) IN (
      date_trunc('day', (now() + interval '7 days') AT TIME ZONE tz),
      date_trunc('day', (now() + interval '3 days') AT TIME ZONE tz),
      date_trunc('day', (now() + interval '1 day')  AT TIME ZONE tz),
      date_trunc('day', now()                        AT TIME ZONE tz),
      date_trunc('day', (now() - interval '29 days') AT TIME ZONE tz)
    );
END;
$$;

-- רק service_role יכול להפעיל — לא anon (מניעת דליפת מיילים של לקוחות)
REVOKE EXECUTE ON FUNCTION public.get_trial_expiry_candidates() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trial_expiry_candidates() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_trial_expiry_candidates() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.get_trial_expiry_candidates() TO service_role;
