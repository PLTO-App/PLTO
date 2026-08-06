-- Migration 116: Disable referral/opportunity commission entirely (temporary)
--
-- Widens the lawyer-only commission block (111, "commission_not_allowed_lawyer")
-- into a universal block covering every vertical. Reason: onboarding lets any
-- user self-select "סוכן נדל"ן" with zero license verification (0 references to
-- "רישיון"/"license" anywhere in index.html, confirmed by grep). Co-brokerage
-- commission between two real estate agents is a legitimate, legal practice —
-- but only when both sides actually hold a broker's license, which we have no
-- way to confirm today. See CLAUDE.md, "עדכון 6/8/2026" under risky idea #3
-- and the follow-up decision to disable commission until (a) legal counsel is
-- consulted and (b) there's real referral volume worth the review — tracked
-- as a trigger, same pattern as the Grow/PayMe and Supabase Pro triggers.
--
-- What stays fully functional: plain commission-free referrals between the
-- three PLTO verticals (accept_lead_referral, no signature step needed),
-- partner_opportunities without commission, and client_consents (client
-- privacy consent for revealing lead details is unrelated to money and stays
-- untouched). What goes dormant: referral_agreements / sign_referral_agreement
-- / the e-signature flow (sign.html) — nothing will insert a commission-bearing
-- row anymore, so nothing will ever need signing. Left in place, not deleted,
-- so re-enabling later (after legal sign-off) is a small, low-risk change
-- instead of rebuilding from scratch.

-- ── 1. _create_lead_referral_core: commission blocked unconditionally ─────

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

  -- Commission disabled for every vertical, temporarily, pending license
  -- verification (was lawyer-only in migration 111). See header note.
  IF p_commission_type <> 'none' THEN
    RAISE EXCEPTION 'commission_not_allowed';
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

-- ── 2. publish_opportunity: commission blocked unconditionally ────────────

CREATE OR REPLACE FUNCTION public.publish_opportunity(
  p_title text, p_description text, p_target_vertical text,
  p_region text, p_city text,
  p_commission_type text DEFAULT 'none', p_commission_value numeric DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_id        uuid;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  IF p_target_vertical NOT IN ('realestate','realestate_lawyer','interior') THEN
    RAISE EXCEPTION 'invalid vertical';
  END IF;
  IF p_region NOT IN ('north','haifa','sharon','center','telaviv','jerusalem','shfela','south') THEN
    RAISE EXCEPTION 'invalid_region';
  END IF;
  IF char_length(coalesce(trim(p_title),'')) < 5 THEN RAISE EXCEPTION 'title_too_short'; END IF;

  -- Commission disabled for every vertical, temporarily (was lawyer-only in
  -- migration 111). See header note in this migration.
  IF coalesce(p_commission_type,'none') <> 'none' THEN
    RAISE EXCEPTION 'commission_not_allowed';
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

-- ── 3. Neutralize the two leftover test rows from feature-development ─────
-- sessions (both on the owner's own test tenants, never a real transaction:
-- one 'awaiting_consent' since 5/7, never proceeded; one 'closed' opportunity
-- from 12/7, closed without ever going through a signed agreement). Without
-- this cleanup the new universal CHECK constraints below would fail to apply.

DELETE FROM referral_agreements
WHERE referral_id IN (SELECT id FROM lead_referrals WHERE commission_type <> 'none');

UPDATE lead_referrals SET commission_type = 'none', commission_value = NULL
WHERE commission_type <> 'none';

UPDATE partner_opportunities SET commission_type = 'none', commission_value = NULL
WHERE commission_type <> 'none';

-- ── 4. Table-level CHECKs: widen from lawyer-only to universal ────────────

ALTER TABLE lead_referrals DROP CONSTRAINT IF EXISTS lead_referrals_lawyer_no_commission;
ALTER TABLE lead_referrals ADD CONSTRAINT lead_referrals_no_commission
  CHECK (commission_type = 'none');

ALTER TABLE partner_opportunities DROP CONSTRAINT IF EXISTS partner_opportunities_lawyer_no_commission;
ALTER TABLE partner_opportunities ADD CONSTRAINT partner_opportunities_no_commission
  CHECK (commission_type = 'none');
