-- Migration 122: send_daily_lead_digest() reads the Make webhook address from Vault
--
-- The address used to be a literal inside this function (migrations 066 and 111),
-- which put it in the public repository and in git history. Only the body changes:
-- the digest logic, the grants and the cron job (plto-leads-daily-digest, which
-- just calls this function) stay as they are.
--
-- BEFORE applying: create the Vault secret named make_owner_webhook_url
-- (select vault.create_secret('<new address>', 'make_owner_webhook_url');), with
-- the address of the NEW Make hook. If the secret is missing the function raises a
-- warning and sends nothing, instead of failing the cron job.
--
-- Before applying, also compare the live function with migration 111 (pg_get_functiondef,
-- address masked). If they differ, stop and reconcile first.

CREATE OR REPLACE FUNCTION public.send_daily_lead_digest()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_count        INT;
  v_tenant_count INT;
  v_leads_html   TEXT;
  v_today        TEXT;
  v_day_start    TIMESTAMPTZ;
  v_url          TEXT;
BEGIN
  v_today     := to_char(now() AT TIME ZONE 'Asia/Jerusalem', 'DD/MM/YYYY');
  v_day_start := date_trunc('day', now() AT TIME ZONE 'Asia/Jerusalem') AT TIME ZONE 'Asia/Jerusalem';

  SELECT
    COUNT(*)::INT,
    COUNT(DISTINCT l.tenant_id)::INT,
    COALESCE(
      string_agg(
        '<tr>' ||
        '<td style="padding:10px 14px;border-bottom:1px solid #E2E8F0;font-weight:600;">' ||
          replace(replace(replace(COALESCE(l.name, '—'), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') ||
        '</td>' ||
        '<td style="padding:10px 14px;border-bottom:1px solid #E2E8F0;direction:ltr;">' ||
          COALESCE(l.phone, '—') ||
        '</td>' ||
        '<td style="padding:10px 14px;border-bottom:1px solid #E2E8F0;">' ||
          CASE COALESCE(t.industry, '')
            WHEN 'realestate'        THEN 'סוכן נדל"ן'
            WHEN 'realestate_lawyer' THEN 'עו"ד'
            WHEN 'interior'          THEN 'עיצוב פנים'
            ELSE 'אחר'
          END ||
        '</td>' ||
        '<td style="padding:10px 14px;border-bottom:1px solid #E2E8F0;">' ||
          replace(replace(replace(COALESCE(t.name, '—'), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') ||
        '</td>' ||
        '</tr>',
        '' ORDER BY l.created_at
      ),
      ''
    )
  INTO v_count, v_tenant_count, v_leads_html
  FROM leads l
  LEFT JOIN tenants t ON t.id = l.tenant_id
  WHERE l.created_at >= v_day_start
    AND l.created_at < now();

  IF v_count > 0 THEN
    SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'make_owner_webhook_url';

    IF v_url IS NULL THEN
      RAISE WARNING 'send_daily_lead_digest: Vault secret make_owner_webhook_url is missing, digest not sent';
      RETURN;
    END IF;

    PERFORM net.http_post(
      url     := v_url,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body    := json_build_object(
        'event',        'lead.daily_digest',
        'date',         v_today,
        'count',        v_count,
        'tenant_count', v_tenant_count,
        'leads_html',   v_leads_html
      )::text
    );
  END IF;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.send_daily_lead_digest() FROM PUBLIC, anon, authenticated;
