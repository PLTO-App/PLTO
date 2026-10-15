-- Migration 122: the daily lead digest sends counts only, through Resend
--
-- Before: send_daily_lead_digest() posted every new lead of the day (name, phone,
-- tenant name) to a Make.com webhook whose address was a literal inside the
-- function (migrations 066 and 111), so personal data of the tenants' customers
-- went to a third party and to the owner's mailbox, and the address sat in the
-- public repository and in git history.
--
-- After: the function emails the owner only totals, through _notify_owner_email()
-- (Resend, key in Vault, the helper added in migration 118):
--   * number of new leads today
--   * number of tenants that received them
--   * a split by vertical
-- No lead names, no phone numbers, no tenant names. Details stay inside the app.
-- Make.com is not involved any more, and no webhook address or new secret is needed.
--
-- Unchanged: the schedule (cron job plto-leads-daily-digest, which only calls this
-- function), the "send only if at least one lead was created today" rule, the day
-- boundary in Asia/Jerusalem, SECURITY DEFINER, search_path and the grants
-- (postgres and service_role only).
--
-- Before applying: compare the live function with migration 111 (pg_get_functiondef,
-- address masked). If they differ, stop and reconcile first.
-- After applying: this migration does not send anything by itself. To check the
-- email, call SELECT public.send_daily_lead_digest(); on a day with at least one lead.

CREATE OR REPLACE FUNCTION public.send_daily_lead_digest()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_count        INT;
  v_tenant_count INT;
  v_rows_html    TEXT;
  v_today        TEXT;
  v_day_start    TIMESTAMPTZ;
BEGIN
  v_today     := to_char(now() AT TIME ZONE 'Asia/Jerusalem', 'DD/MM/YYYY');
  v_day_start := date_trunc('day', now() AT TIME ZONE 'Asia/Jerusalem') AT TIME ZONE 'Asia/Jerusalem';

  SELECT COUNT(*)::INT, COUNT(DISTINCT l.tenant_id)::INT
  INTO v_count, v_tenant_count
  FROM leads l
  WHERE l.created_at >= v_day_start
    AND l.created_at < now();

  IF v_count > 0 THEN
    SELECT COALESCE(
      string_agg(
        '<tr>' ||
        '<td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;">' || g.label || '</td>' ||
        '<td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;font-weight:600;">' || g.n || '</td>' ||
        '</tr>',
        '' ORDER BY g.n DESC, g.label
      ),
      ''
    )
    INTO v_rows_html
    FROM (
      SELECT
        CASE COALESCE(t.industry, '')
          WHEN 'realestate'        THEN 'סוכן נדל"ן'
          WHEN 'realestate_lawyer' THEN 'עו"ד'
          WHEN 'interior'          THEN 'עיצוב פנים'
          ELSE 'אחר'
        END AS label,
        COUNT(*)::INT AS n
      FROM leads l
      LEFT JOIN tenants t ON t.id = l.tenant_id
      WHERE l.created_at >= v_day_start
        AND l.created_at < now()
      GROUP BY 1
    ) g;

    PERFORM public._notify_owner_email(
      'PLTO: ' || v_count || ' לידים חדשים היום',
      '<div dir="rtl" style="font-family:Arial,Helvetica,sans-serif;color:#0F1F3D;max-width:480px;">' ||
      '<h2 style="margin:0 0 8px;font-size:18px;">סיכום לידים יומי, ' || v_today || '</h2>' ||
      '<p style="margin:0 0 12px;font-size:14px;">נוצרו היום ' || v_count || ' לידים אצל ' || v_tenant_count || ' עסקים.</p>' ||
      '<table style="width:100%;border-collapse:collapse;font-size:14px;">' || v_rows_html || '</table>' ||
      '</div>'
    );
  END IF;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.send_daily_lead_digest() FROM PUBLIC, anon, authenticated;
