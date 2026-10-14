-- Migration 120: create_client_page() builds cta_url on realestate.plto.app
--
-- After the move of the CRM to the realestate.plto.app subdomain, the apex
-- plto.app no longer serves the app (it is reserved for the future company
-- site), so referral links built as https://plto.app/?lref=... return 404.
-- Only the base URL changes; the logic, rate limit, tenant scoping and grants
-- are identical to migration 104. Existing rows are not touched (client_pages
-- was empty when this migration was written).

CREATE OR REPLACE FUNCTION public.create_client_page(
  p_token       text,
  p_title       text,
  p_headline    text,
  p_body_text   text,
  p_cta_label   text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_ref       lead_referrals%ROWTYPE;
  v_slug      text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  -- Rate limit: 10 pages per user per 24h (matches create_lead_referral's threshold, 061)
  IF (SELECT count(*) FROM client_pages cp
      WHERE cp.created_by_user_id = auth.uid() AND cp.created_at > now() - interval '24 hours') >= 10 THEN
    RAISE EXCEPTION 'page_rate_limit';
  END IF;

  SELECT * INTO v_ref FROM lead_referrals WHERE token = p_token AND from_tenant_id = v_tenant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'referral not found'; END IF;

  INSERT INTO client_pages (
    tenant_id, page_type, referral_id, title, headline, body_text, cta_label, cta_url, created_by_user_id
  ) VALUES (
    v_tenant_id, 'referral_invite', v_ref.id,
    left(coalesce(p_title, ''), 120),
    left(coalesce(p_headline, ''), 120),
    left(coalesce(p_body_text, ''), 600),
    left(coalesce(p_cta_label, 'הצטרפות'), 40),
    -- cta_url is derived server-side from the referral's own token — never
    -- accepted as a parameter from the caller (open-redirect/phishing guard).
    'https://realestate.plto.app/?lref=' || v_ref.token,
    auth.uid()
  )
  RETURNING slug INTO v_slug;

  RETURN jsonb_build_object('slug', v_slug);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.create_client_page(text,text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_client_page(text,text,text,text,text) TO authenticated;
