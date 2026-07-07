-- Migration 072: External Referral Signing (חתימת הסכם ללא חשבון Liders)
--
-- Enables sending a commission-locked referral to someone who is NOT a Liders
-- user (contractor, window installer, etc.). The recipient visits sign.html,
-- reads the agreement, signs with their name + canvas signature — all without
-- any account. The sender gets legal-grade proof; the recipient optionally
-- joins the trial afterward.
--
-- Changes:
--   1. lead_referrals.to_vertical: add 'other' + new col external_profession
--   2. lead_referrals.status: add 'signed_external'
--   3. referral_agreements: add external_signer_phone
--   4. _vertical_label_he: handle 'other'
--   5. _build_referral_agreement_text: accept optional p_to_profession override
--   6. _create_lead_referral_core: allow 'other' vertical + p_external_profession
--   7. create_lead_referral: expose p_external_profession
--   8. get_lead_referral_preview: return external_profession
--   9. list_my_lead_referrals: include external_profession
--  10. NEW get_referral_agreement_anon: anon-accessible agreement fetch
--  11. NEW sign_referral_agreement_anon: anon-accessible signing

-- ── 1. lead_referrals schema ──────────────────────────────────────────────

ALTER TABLE lead_referrals DROP CONSTRAINT IF EXISTS lead_referrals_to_vertical_check;
ALTER TABLE lead_referrals ADD CONSTRAINT lead_referrals_to_vertical_check CHECK (
  to_vertical IN ('realestate','realestate_lawyer','interior','other')
);

ALTER TABLE lead_referrals ADD COLUMN IF NOT EXISTS external_profession text;

-- Add signed_external to status machine
ALTER TABLE lead_referrals DROP CONSTRAINT IF EXISTS lead_referrals_status_check;
ALTER TABLE lead_referrals ADD CONSTRAINT lead_referrals_status_check CHECK (
  status IN (
    'awaiting_consent','consent_declined','sent','opened',
    'awaiting_signature','declined','accepted','converted',
    'expired','cancelled',
    'signed_external'   -- signed by someone without a Liders account
  )
);

-- ── 2. referral_agreements schema ─────────────────────────────────────────

ALTER TABLE referral_agreements ADD COLUMN IF NOT EXISTS external_signer_phone text;

-- ── 3. _vertical_label_he: add 'other' ────────────────────────────────────

CREATE OR REPLACE FUNCTION public._vertical_label_he(p_vertical text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE p_vertical
    WHEN 'realestate'        THEN 'סוכן נדל"ן'
    WHEN 'realestate_lawyer' THEN 'עו"ד נדל"ן'
    WHEN 'interior'          THEN 'מעצב פנים'
    WHEN 'other'             THEN 'בעל מקצוע'
    ELSE 'בעל מקצוע'
  END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._vertical_label_he(text) FROM PUBLIC, anon, authenticated;

-- ── 4. _build_referral_agreement_text: add optional profession override ───

CREATE OR REPLACE FUNCTION public._build_referral_agreement_text(
  p_referrer_name text, p_to_vertical text, p_lead_first_name text,
  p_commission_type text, p_commission_value numeric,
  p_to_profession text DEFAULT NULL
) RETURNS text LANGUAGE sql STABLE AS $fn$
  SELECT 'הסכם עמלת הפניה — Liders CRM' || E'\n'
      || '════════════════════════════' || E'\n\n'
      || 'המפנה: ' || p_referrer_name || E'\n'
      || 'המקבל: ' || coalesce(nullif(trim(p_to_profession),''), _vertical_label_he(p_to_vertical))
                   || ' (שמו המלא יופיע בחתימה)' || E'\n'
      || 'הליד המועבר: ' || coalesce(nullif(p_lead_first_name,''), 'ליד') || E'\n'
      || 'תאריך: ' || to_char(now() AT TIME ZONE 'Asia/Jerusalem', 'DD/MM/YYYY') || E'\n\n'
      || '1. המפנה מעביר למקבל ליד לטיפול מקצועי בתחומו של המקבל.' || E'\n'
      || '2. פרטי הליד המלאים ייחשפו למקבל רק לאחר חתימתו על הסכם זה.' || E'\n'
      || '3. אם תיסגר עסקה שמקורה בליד זה, ישלם המקבל למפנה עמלת הפניה בשיעור: '
      || _commission_label_he(p_commission_type, p_commission_value) || '.' || E'\n'
      || '4. התשלום יבוצע בתוך 30 יום ממועד קבלת התמורה בעסקה, כנגד חשבונית כדין.' || E'\n'
      || '5. המקבל מתחייב לטפל בליד במקצועיות ולעדכן את המפנה על סגירת עסקה שמקורה בהפניה.' || E'\n'
      || '6. הסכם זה תקף להפניה זו בלבד ואינו יוצר יחסי שותפות או שליחות בין הצדדים.' || E'\n'
      || '7. Liders CRM היא פלטפורמה טכנולוגית בלבד ואינה צד להסכם, אינה גובה את העמלה ואינה אחראית לאכיפתו.' || E'\n'
      || '8. החתימה הדיגיטלית שלהלן, בצירוף תיעוד מועד החתימה וזהות החותם, מהווה אישור הדדי מחייב בין הצדדים.' || E'\n';
$fn$;
REVOKE EXECUTE ON FUNCTION public._build_referral_agreement_text(text,text,text,text,numeric,text) FROM PUBLIC, anon, authenticated;

-- ── 5. _create_lead_referral_core: allow 'other' + external_profession ────

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
      'referrer_name',     coalesce(v_tenant.name, 'משתמש Liders CRM'),
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
        coalesce(v_tenant.name, 'משתמש Liders CRM'), p_to_vertical,
        split_part(coalesce(v_lead.name,''), ' ', 1),
        p_commission_type, p_commission_value,
        p_external_profession
      )
    );
  END IF;

  IF p_require_consent THEN
    v_consent_text := 'היי ' || split_part(coalesce(v_lead.name,''), ' ', 1) || ', '
      || coalesce(v_tenant.name, 'משתמש Liders CRM')
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

-- ── 6. create_lead_referral: expose p_external_profession ─────────────────

CREATE OR REPLACE FUNCTION public.create_lead_referral(
  p_lead_id uuid, p_to_vertical text, p_to_name text, p_to_phone text, p_context text,
  p_commission_type text DEFAULT 'none',
  p_commission_value numeric DEFAULT NULL,
  p_require_consent boolean DEFAULT false,
  p_external_profession text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  IF (SELECT count(*) FROM lead_referrals
      WHERE from_user_id = auth.uid() AND created_at > now() - interval '24 hours') >= 10 THEN
    RAISE EXCEPTION 'referral_rate_limit';
  END IF;

  RETURN _create_lead_referral_core(
    v_tenant_id, auth.uid(), p_lead_id,
    p_to_vertical, p_to_name, p_to_phone, p_context,
    coalesce(p_commission_type, 'none'), p_commission_value,
    coalesce(p_require_consent, false),
    NULL, NULL,
    p_external_profession
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.create_lead_referral(uuid,text,text,text,text,text,numeric,boolean,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_lead_referral(uuid,text,text,text,text,text,numeric,boolean,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.create_lead_referral(uuid,text,text,text,text,text,numeric,boolean,text) TO authenticated;

-- ── 7. get_lead_referral_preview: return external_profession ──────────────

CREATE OR REPLACE FUNCTION public.get_lead_referral_preview(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_ref lead_referrals%ROWTYPE;
BEGIN
  SELECT * INTO v_ref FROM lead_referrals WHERE token = p_token;
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false); END IF;

  IF v_ref.status IN ('sent','opened','awaiting_signature') AND v_ref.expires_at < now() THEN
    UPDATE lead_referrals SET status = 'expired' WHERE id = v_ref.id;
    RETURN jsonb_build_object('found', false);
  END IF;
  IF v_ref.status NOT IN ('sent','opened','awaiting_signature') THEN
    RETURN jsonb_build_object('found', false, 'status', v_ref.status);
  END IF;
  IF v_ref.status = 'sent' THEN
    UPDATE lead_referrals SET status = 'opened' WHERE id = v_ref.id;
  END IF;

  RETURN jsonb_build_object(
    'found',               true,
    'referrer_name',       v_ref.lead_snapshot->>'referrer_name',
    'to_vertical',         v_ref.to_vertical,
    'external_profession', v_ref.external_profession,
    'lead_first_name',     split_part(coalesce(v_ref.lead_snapshot->>'name',''), ' ', 1),
    'locked',              v_ref.commission_type <> 'none',
    'commission_type',     v_ref.commission_type,
    'commission_value',    v_ref.commission_value,
    'commission_label',    CASE WHEN v_ref.commission_type <> 'none'
                               THEN _commission_label_he(v_ref.commission_type, v_ref.commission_value)
                               ELSE NULL END
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_lead_referral_preview(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_lead_referral_preview(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_referral_preview(text) TO authenticated;

-- ── 8. list_my_lead_referrals: include external_profession ────────────────

DROP FUNCTION IF EXISTS public.list_my_lead_referrals();

CREATE OR REPLACE FUNCTION public.list_my_lead_referrals()
RETURNS TABLE (
  id uuid, direction text, lead_name text, to_vertical text, to_name text,
  status text, commission_type text, commission_value numeric,
  consent_status text, agreement_status text,
  other_party text, token text, created_at timestamptz,
  external_profession text
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $fn$
  -- referrals I sent
  SELECT r.id, 'sent'::text,
         r.lead_snapshot->>'name',
         r.to_vertical, r.to_name, r.status,
         r.commission_type, r.commission_value,
         c.status, a.status,
         coalesce(t.name, a.signer_name, r.to_name),
         r.token, r.created_at,
         r.external_profession
  FROM lead_referrals r
  LEFT JOIN client_consents c      ON c.referral_id = r.id
  LEFT JOIN referral_agreements a  ON a.referral_id = r.id
  LEFT JOIN tenants t              ON t.id = r.accepted_by_tenant_id
  WHERE r.from_tenant_id = get_my_tenant_id()
  UNION ALL
  -- referrals directed to me (board) or accepted by me
  SELECT r.id, 'received'::text,
         CASE WHEN r.status IN ('accepted','converted')
              THEN r.lead_snapshot->>'name'
              ELSE split_part(coalesce(r.lead_snapshot->>'name',''), ' ', 1) END,
         r.to_vertical, r.to_name, r.status,
         r.commission_type, r.commission_value,
         c.status, a.status,
         r.lead_snapshot->>'referrer_name',
         CASE WHEN r.status IN ('sent','opened','awaiting_signature','awaiting_consent')
              THEN r.token ELSE NULL END,
         r.created_at,
         r.external_profession
  FROM lead_referrals r
  LEFT JOIN client_consents c      ON c.referral_id = r.id
  LEFT JOIN referral_agreements a  ON a.referral_id = r.id
  WHERE r.from_tenant_id <> get_my_tenant_id()
    AND (r.accepted_by_tenant_id = get_my_tenant_id() OR r.to_tenant_id = get_my_tenant_id())
  ORDER BY created_at DESC
  LIMIT 50;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_my_lead_referrals() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_my_lead_referrals() FROM anon;
GRANT  EXECUTE ON FUNCTION public.list_my_lead_referrals() TO authenticated;

-- ── 9. get_referral_agreement_anon: anon-accessible agreement text ─────────
-- Used by sign.html before the signer has a Liders account.
-- Identical security posture to get_lead_referral_preview: token space is
-- 128-bit random hex; minimal data exposure (no internal IDs, no full lead).

CREATE OR REPLACE FUNCTION public.get_referral_agreement_anon(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_ref lead_referrals%ROWTYPE;
  v_agr referral_agreements%ROWTYPE;
BEGIN
  SELECT * INTO v_ref FROM lead_referrals WHERE token = p_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'referral_not_found'; END IF;

  IF v_ref.status IN ('sent','opened','awaiting_signature') AND v_ref.expires_at < now() THEN
    UPDATE lead_referrals SET status = 'expired' WHERE id = v_ref.id;
    RAISE EXCEPTION 'referral_expired';
  END IF;
  IF v_ref.status NOT IN ('sent','opened','awaiting_signature') THEN
    RAISE EXCEPTION 'referral_used';
  END IF;
  IF v_ref.commission_type = 'none' THEN RAISE EXCEPTION 'no_agreement_needed'; END IF;

  SELECT * INTO v_agr FROM referral_agreements WHERE referral_id = v_ref.id;
  IF NOT FOUND THEN RAISE EXCEPTION 'agreement_not_found'; END IF;

  -- Advance status so the sender sees "צופה בהסכם"
  IF v_ref.status = 'sent' THEN
    UPDATE lead_referrals SET status = 'opened' WHERE id = v_ref.id;
  END IF;

  RETURN jsonb_build_object(
    'agreement_text',      v_agr.agreement_text,
    'commission_label',    _commission_label_he(v_agr.commission_type, v_agr.commission_value),
    'referrer_name',       v_ref.lead_snapshot->>'referrer_name',
    'lead_first_name',     split_part(coalesce(v_ref.lead_snapshot->>'name',''), ' ', 1),
    'to_vertical',         v_ref.to_vertical,
    'external_profession', v_ref.external_profession
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_referral_agreement_anon(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_referral_agreement_anon(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.get_referral_agreement_anon(text) TO authenticated;

-- ── 10. sign_referral_agreement_anon: sign without a Liders account ────────
-- After signing: returns full lead details (name + phone) as the reward.
-- The referral status becomes 'signed_external' — it does NOT create a lead
-- in any pipeline (no tenant). The sender has legal proof; the signer is
-- shown a "join trial" CTA to optionally onboard.

CREATE OR REPLACE FUNCTION public.sign_referral_agreement_anon(
  p_token text, p_signer_name text, p_signer_phone text, p_signature_image text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_ref       lead_referrals%ROWTYPE;
  v_agr       referral_agreements%ROWTYPE;
  v_headers   jsonb;
  v_signed_at timestamptz := now();
BEGIN
  IF coalesce(trim(p_signer_name), '') = '' THEN RAISE EXCEPTION 'signer_name_required'; END IF;
  IF p_signature_image IS NULL OR p_signature_image NOT LIKE 'data:image/%' THEN
    RAISE EXCEPTION 'signature_required';
  END IF;
  IF length(p_signature_image) > 150000 THEN RAISE EXCEPTION 'signature_too_large'; END IF;

  SELECT * INTO v_ref FROM lead_referrals WHERE token = p_token FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'referral_not_found'; END IF;
  IF v_ref.status NOT IN ('sent','opened','awaiting_signature') THEN
    RAISE EXCEPTION 'referral_used';
  END IF;
  IF v_ref.expires_at < now() THEN
    UPDATE lead_referrals SET status = 'expired' WHERE id = v_ref.id;
    RAISE EXCEPTION 'referral_expired';
  END IF;
  IF v_ref.commission_type = 'none' THEN RAISE EXCEPTION 'no_agreement_needed'; END IF;

  SELECT * INTO v_agr FROM referral_agreements WHERE referral_id = v_ref.id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'agreement_not_found'; END IF;
  IF v_agr.status <> 'pending' THEN RAISE EXCEPTION 'agreement_not_pending'; END IF;

  v_headers := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);

  UPDATE referral_agreements SET
    status                = 'signed',
    signer_name           = left(trim(p_signer_name), 120),
    signature_image       = p_signature_image,
    signature_hash        = encode(sha256(convert_to(
                              v_agr.agreement_text || '|' || trim(p_signer_name) || '|' ||
                              v_signed_at::text    || '|' || v_ref.token, 'UTF8')), 'hex'),
    external_signer_phone = left(coalesce(trim(p_signer_phone), ''), 30),
    signer_ip             = left(coalesce(
                              nullif(v_headers->>'cf-connecting-ip',''),
                              nullif(v_headers->>'x-real-ip',''),
                              v_headers->>'x-forwarded-for',''
                            ), 100),
    signer_user_agent     = left(coalesce(v_headers->>'user-agent',''), 300),
    signed_at             = v_signed_at
  WHERE id = v_agr.id;

  UPDATE lead_referrals SET status = 'signed_external' WHERE id = v_ref.id;

  -- Reveal full lead details as the reward for signing
  RETURN jsonb_build_object(
    'ok',               true,
    'lead_name',        v_ref.lead_snapshot->>'name',
    'lead_phone',       v_ref.lead_snapshot->>'phone',
    'lead_area',        v_ref.lead_snapshot->>'area',
    'referrer_name',    v_ref.lead_snapshot->>'referrer_name',
    'commission_label', _commission_label_he(v_agr.commission_type, v_agr.commission_value),
    'agreement_id',     v_agr.id
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.sign_referral_agreement_anon(text,text,text,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.sign_referral_agreement_anon(text,text,text,text) TO anon;
GRANT  EXECUTE ON FUNCTION public.sign_referral_agreement_anon(text,text,text,text) TO authenticated;
