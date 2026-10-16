-- Migration 125: escape user supplied text in the owner alert emails
--
-- _notify_owner_new_tenant() and check_and_notify_trial14() put the tenant name,
-- industry and billing email straight into the HTML of an email to the owner. The
-- tenant name is chosen by whoever signs up, so a name like "<a href=...>" ended up
-- as live HTML in the owner's mailbox. This migration adds an internal escape helper
-- and uses it for every user supplied value in both emails. Subjects are flattened to
-- one line. Nothing else changes: same recipients, same triggers, same cron job, same
-- grants (EXECUTE on both functions stays limited to postgres and service_role).

CREATE OR REPLACE FUNCTION public._html_escape(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $fn$
  SELECT replace(replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$fn$;
REVOKE EXECUTE ON FUNCTION public._html_escape(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._notify_owner_new_tenant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  PERFORM public._notify_owner_email(
    'נרשם עסק חדש ל-PLTO: ' || left(regexp_replace(coalesce(NEW.name, NEW.slug, ''), '\s+', ' ', 'g'), 100),
    '<p>נפתח חשבון חדש במערכת.</p>'
    || '<p><b>שם:</b> ' || public._html_escape(coalesce(NEW.name, '—')) || '</p>'
    || '<p><b>תחום:</b> ' || public._html_escape(coalesce(NEW.industry, '—')) || '</p>'
    || '<p><b>אימייל:</b> ' || public._html_escape(coalesce(NEW.billing_email, '—')) || '</p>'
    || '<p><b>נרשם ב:</b> ' || to_char(NEW.created_at AT TIME ZONE 'Asia/Jerusalem', 'DD/MM/YYYY HH24:MI') || '</p>'
  );
  NEW.owner_new_tenant_notified_at := now();
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.check_and_notify_trial14()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT t.id, t.name, t.slug, t.billing_email, t.industry, t.created_at
    FROM tenants t
    WHERE t.owner_trial14_notified_at IS NULL
      AND t.created_at <= now() - interval '14 days'
      AND EXISTS (SELECT 1 FROM leads l WHERE l.tenant_id = t.id)
  LOOP
    PERFORM public._notify_owner_email(
      'עסק פעיל 14 יום ב-PLTO: ' || left(regexp_replace(coalesce(r.name, r.slug, ''), '\s+', ' ', 'g'), 100) || ' — זמן לחבר סליקה',
      '<p>הטננט הבא עובר 14 יום מההרשמה ויש לו פעילות אמיתית (לפחות ליד אחד).</p>'
      || '<p><b>שם:</b> ' || public._html_escape(coalesce(r.name, '—')) || '</p>'
      || '<p><b>תחום:</b> ' || public._html_escape(coalesce(r.industry, '—')) || '</p>'
      || '<p><b>אימייל:</b> ' || public._html_escape(coalesce(r.billing_email, '—')) || '</p>'
      || '<p><b>נרשם ב:</b> ' || to_char(r.created_at AT TIME ZONE 'Asia/Jerusalem', 'DD/MM/YYYY') || '</p>'
      || '<p>מומלץ לוודא שקישורי הסליקה של Grow/PayMe מוכנים לחבילה שלו.</p>'
    );
    UPDATE tenants SET owner_trial14_notified_at = now() WHERE id = r.id;
  END LOOP;
END;
$fn$;
