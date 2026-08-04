-- Migration 111: Reconcile lawyer-commission-block drift + relabel to "עו"ד"
--
-- Part of expanding the `realestate_lawyer` vertical from "עו"ד נדל"ן" (real estate
-- lawyer) to a general lawyer vertical, per the ethics review in
-- LEGAL_COMPLIANCE_LAWYER_REFERRALS.md (rule 11ב of the Israel Bar Association's
-- Professional Ethics Rules, 1986: a lawyer may not accept a client referred by a
-- for-profit body that advertises referral services).
--
-- DRIFT NOTE: a migration named "block_lawyer_referral_commission" (2026-07-23,
-- version 20260723202452) is already live in this project, applied directly against
-- the database with no matching file in this repo. It already adds a
-- `commission_not_allowed_lawyer` guard to both `_create_lead_referral_core` and
-- `publish_opportunity`. Verified live via pg_get_functiondef before writing this
-- file. Sections 1-2 below reproduce that already-live behavior byte-for-byte
-- (pulled via pg_get_functiondef) purely to close the repo/DB drift — no behavior
-- change. Zero live tenants currently have industry='realestate_lawyer', so there is
-- no data-migration risk either way.

-- ── 1. _create_lead_referral_core: reproduce the already-live guard ───────────────

CREATE OR REPLACE FUNCTION public._create_lead_referral_core(
  p_tenant_id uuid, p_user_id uuid, p_lead_id uuid,
  p_to_vertical text, p_to_name text, p_to_phone text, p_context text,
  p_commission_type text, p_commission_value numeric, p_require_consent boolean,
  p_to_tenant_id uuid, p_opportunity_id uuid,
  p_external_profession text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_lead          leads%ROWTYPE;
  v_tenant        tenants%ROWTYPE;
  v_referral_id   uuid;
  v_token         text;
  v_consent_token text;
  v_consent_text  text;
BEGIN
  IF p_to_vertical NOT IN ('realestate','realestate_lawyer','interior','other') THEN
    RAISE EXCEPTION 'invalid vertical';
  END IF;
  IF p_commission_type NOT IN ('none','percent','fixed') THEN
    RAISE EXCEPTION 'invalid_commission_type';
  END IF;
  IF p_commission_type = 'none' AND p_commission_value IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_commission_value';
  END IF;
  IF p_commission_type = 'percent' AND (p_commission_value IS NULL OR p_commission_value <= 0 OR p_commission_value > 50) THEN
    RAISE EXCEPTION 'invalid_commission_value';
  END IF;
  IF p_commission_type = 'fixed' AND (p_commission_value IS NULL OR p_commission_value <= 0 OR p_commission_value > 1000000) THEN
    RAISE EXCEPTION 'invalid_commission_value';
  END IF;

  SELECT * INTO v_lead FROM leads WHERE id = p_lead_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'lead not found'; END IF;
  SELECT * INTO v_tenant FROM tenants WHERE id = p_tenant_id;

  IF p_commission_type <> 'none'
     AND (p_to_vertical = 'realestate_lawyer' OR coalesce(v_tenant.industry, 'other') = 'realestate_lawyer') THEN
    RAISE EXCEPTION 'commission_not_allowed_lawyer';
  END IF;

  INSERT INTO lead_referrals (
    from_tenant_id, from_user_id, lead_id, lead_snapshot,
    to_vertical, to_name, to_phone,
    commission_type, commission_value, to_tenant_id, opportunity_id, status,
    external_profession
  )
  VALUES (
    p_tenant_id, p_user_id, p_lead_id,
    jsonb_build_object(
      'name',              v_lead.name,
      'phone',             v_lead.phone,
      'area',              v_lead.desired_area,
      'context',           left(coalesce(p_context, ''), 300),
      'referrer_name',     coalesce(v_tenant.name, 'משתמש PLTO'),
      'referrer_industry', coalesce(v_tenant.industry, 'other')
    ),
    p_to_vertical,
    left(coalesce(p_to_name,''), 80),
    left(coalesce(p_to_phone,''), 30),
    p_commission_type,
    CASE WHEN p_commission_type = 'none' THEN NULL ELSE p_commission_value END,
    p_to_tenant_id, p_opportunity_id,
    CASE WHEN p_require_consent THEN 'awaiting_consent' ELSE 'sent' END,
    CASE WHEN p_to_vertical = 'other' THEN left(trim(coalesce(p_external_profession,'')), 80) ELSE NULL END
  )
  RETURNING id, token INTO v_referral_id, v_token;

  IF p_commission_type <> 'none' THEN
    INSERT INTO referral_agreements (
      referral_id, from_tenant_id, from_user_id,
      commission_type, commission_value, agreement_text
    ) VALUES (
      v_referral_id, p_tenant_id, p_user_id,
      p_commission_type, p_commission_value,
      _build_referral_agreement_text(
        coalesce(v_tenant.name, 'משתמש PLTO'), p_to_vertical,
        split_part(coalesce(v_lead.name,''), ' ', 1),
        p_commission_type, p_commission_value,
        p_external_profession
      )
    );
  END IF;

  IF p_require_consent THEN
    v_consent_text := 'היי ' || split_part(coalesce(v_lead.name,''), ' ', 1) || ', '
      || coalesce(v_tenant.name, 'משתמש PLTO')
      || ' מבקש את אישורך להעביר את פרטיך (שם וטלפון בלבד) ל'
      || coalesce(nullif(trim(p_external_profession),''), _vertical_label_he(p_to_vertical))
      || ' שותף, לצורך המשך טיפול מקצועי. הפרטים יועברו רק אם תאשר.';

    INSERT INTO client_consents (
      referral_id, tenant_id, requested_by, lead_id, client_name, client_phone, consent_text
    ) VALUES (
      v_referral_id, p_tenant_id, p_user_id, p_lead_id,
      v_lead.name, v_lead.phone, v_consent_text
    )
    RETURNING token INTO v_consent_token;
  END IF;

  RETURN jsonb_build_object(
    'referral_id',   v_referral_id,
    'token',         v_token,
    'consent_token', v_consent_token,
    'client_phone',  v_lead.phone,
    'client_name',   v_lead.name
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._create_lead_referral_core(uuid,uuid,uuid,text,text,text,text,text,numeric,boolean,uuid,uuid,text) FROM PUBLIC, anon, authenticated;

-- ── 2. publish_opportunity: reproduce the already-live guard ──────────────────────

CREATE OR REPLACE FUNCTION public.publish_opportunity(
  p_title text, p_description text, p_target_vertical text,
  p_region text, p_city text,
  p_commission_type text DEFAULT 'none', p_commission_value numeric DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_id        uuid;
  v_industry  text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  IF p_target_vertical NOT IN ('realestate','realestate_lawyer','interior') THEN
    RAISE EXCEPTION 'invalid vertical';
  END IF;
  IF p_region NOT IN ('north','haifa','sharon','center','telaviv','jerusalem','shfela','south') THEN
    RAISE EXCEPTION 'invalid_region';
  END IF;
  IF char_length(coalesce(trim(p_title),'')) < 5 THEN RAISE EXCEPTION 'title_too_short'; END IF;

  SELECT industry INTO v_industry FROM tenants WHERE id = v_tenant_id;
  IF coalesce(p_commission_type,'none') <> 'none'
     AND (p_target_vertical = 'realestate_lawyer' OR coalesce(v_industry, 'other') = 'realestate_lawyer') THEN
    RAISE EXCEPTION 'commission_not_allowed_lawyer';
  END IF;

  -- Rate limit: 5 opportunities per user per 24h
  IF (SELECT count(*) FROM partner_opportunities
      WHERE created_by = auth.uid() AND created_at > now() - interval '24 hours') >= 5 THEN
    RAISE EXCEPTION 'opportunity_rate_limit';
  END IF;

  INSERT INTO partner_opportunities (
    tenant_id, created_by, title, description, target_vertical, region, city,
    commission_type, commission_value
  ) VALUES (
    v_tenant_id, auth.uid(),
    left(trim(p_title), 120),
    nullif(left(coalesce(p_description,''), 1000), ''),
    p_target_vertical, p_region, nullif(left(coalesce(trim(p_city),''), 80), ''),
    coalesce(p_commission_type, 'none'),
    CASE WHEN coalesce(p_commission_type,'none') = 'none' THEN NULL ELSE p_commission_value END
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.publish_opportunity(text,text,text,text,text,text,numeric) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.publish_opportunity(text,text,text,text,text,text,numeric) TO authenticated;

-- ── 3. Relabel "עו"ד נדל"ן" → "עו"ד" (vertical broadened beyond real estate) ──────

CREATE OR REPLACE FUNCTION public._vertical_label_he(p_vertical text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $fn$
  SELECT CASE p_vertical
    WHEN 'realestate'        THEN 'סוכן נדל"ן'
    WHEN 'realestate_lawyer' THEN 'עו"ד'
    WHEN 'interior'          THEN 'מעצב פנים'
    WHEN 'other'             THEN 'בעל מקצוע'
    ELSE 'בעל מקצוע'
  END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._vertical_label_he(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.send_daily_lead_digest()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_count        INT;
  v_tenant_count INT;
  v_leads_html   TEXT;
  v_today        TEXT;
  v_day_start    TIMESTAMPTZ;
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
    PERFORM net.http_post(
      url     := 'https://hook.eu1.make.com/f0nzngm6gdokri5naqu7enbay538ay8i',
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

-- ── 4. Defense-in-depth table-level CHECKs (no bypass path exists today, but ─────
--      matches the existing CHECK-constraint pattern already on these tables) ────

ALTER TABLE lead_referrals DROP CONSTRAINT IF EXISTS lead_referrals_lawyer_no_commission;
ALTER TABLE lead_referrals ADD CONSTRAINT lead_referrals_lawyer_no_commission
  CHECK (NOT (to_vertical = 'realestate_lawyer' AND commission_type <> 'none'));

ALTER TABLE partner_opportunities DROP CONSTRAINT IF EXISTS partner_opportunities_lawyer_no_commission;
ALTER TABLE partner_opportunities ADD CONSTRAINT partner_opportunities_lawyer_no_commission
  CHECK (NOT (target_vertical = 'realestate_lawyer' AND commission_type <> 'none'));
