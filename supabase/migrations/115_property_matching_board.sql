-- Migration 115: Property/Buyer Matching Board (לוח התאמות נכס↔קונה)
--
-- Two-sided classifieds board for realestate-vertical tenants only:
--   'listing'    — an agent holding an exclusive property advertises it for
--                   exposure to other agents' buyers.
--   'buyer_need' — an agent representing a buyer/renter posts budget+area
--                   only (never the client's name/phone) looking for a match.
--
-- Deliberately NOT built on top of partner_opportunities (065): that table's
-- select_opportunity_applicant() always produces a commission-bearing
-- lead_referral. Here no money crosses tenants through the platform at all —
-- each agent already has their own separate deal with their own client, so
-- there is no commission/agreement/consent ceremony to build. Contact is a
-- direct wa.me link using the poster's tenant phone, exposed immediately
-- (no anonymize-then-reveal step, unlike partner_opportunities).
--
-- Security model (mirrors 061/065): RLS enabled with zero policies,
-- SECURITY DEFINER RPCs only, server-derived tenant identity, rate limits.

CREATE TABLE IF NOT EXISTS market_board_posts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  created_by          uuid NOT NULL,
  post_type           text NOT NULL CHECK (post_type IN ('listing','buyer_need')),
  region              text NOT NULL CHECK (region IN
                      ('north','haifa','sharon','center','telaviv','jerusalem','shfela','south')),
  city                text,
  property_type       text CHECK (property_type IN
                      ('apartment','house','penthouse','commercial','land')),
  price_min           numeric(14,2),
  price_max           numeric(14,2),
  rooms               numeric(3,1),
  description         text CHECK (description IS NULL OR char_length(description) <= 500),
  source_lead_id      uuid REFERENCES leads(id) ON DELETE SET NULL,
  source_property_id  uuid REFERENCES properties(id) ON DELETE SET NULL,
  status              text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','expired')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz NOT NULL DEFAULT now() + interval '30 days',
  CONSTRAINT market_board_posts_price_range CHECK (
    price_min IS NULL OR price_max IS NULL OR price_min <= price_max
  )
);

CREATE INDEX IF NOT EXISTS idx_market_board_open
  ON market_board_posts(post_type, region, created_at DESC) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_market_board_tenant
  ON market_board_posts(tenant_id, created_at DESC);

ALTER TABLE market_board_posts ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: all access via SECURITY DEFINER RPCs below.

-- ── publish_market_post() ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.publish_market_post(
  p_post_type          text,
  p_region             text,
  p_city               text,
  p_property_type      text,
  p_price_min          numeric DEFAULT NULL,
  p_price_max          numeric DEFAULT NULL,
  p_rooms              numeric DEFAULT NULL,
  p_description        text DEFAULT NULL,
  p_source_lead_id     uuid DEFAULT NULL,
  p_source_property_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_industry  text;
  v_lead      leads%ROWTYPE;
  v_prop      properties%ROWTYPE;
  v_price_min numeric := p_price_min;
  v_price_max numeric := p_price_max;
  v_rooms     numeric := p_rooms;
  v_city      text := p_city;
  v_ptype     text := p_property_type;
  v_id        uuid;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  SELECT industry INTO v_industry FROM tenants WHERE id = v_tenant_id;
  IF coalesce(v_industry, 'other') <> 'realestate' THEN
    RAISE EXCEPTION 'vertical_not_supported';
  END IF;

  IF p_post_type NOT IN ('listing','buyer_need') THEN
    RAISE EXCEPTION 'invalid_post_type';
  END IF;
  IF p_region NOT IN ('north','haifa','sharon','center','telaviv','jerusalem','shfela','south') THEN
    RAISE EXCEPTION 'invalid_region';
  END IF;
  IF p_property_type IS NOT NULL AND p_property_type NOT IN
     ('apartment','house','penthouse','commercial','land') THEN
    RAISE EXCEPTION 'invalid_property_type';
  END IF;

  -- Rate limit: 5 posts per user per 24h
  IF (SELECT count(*) FROM market_board_posts
      WHERE created_by = auth.uid() AND created_at > now() - interval '24 hours') >= 5 THEN
    RAISE EXCEPTION 'market_post_rate_limit';
  END IF;

  IF p_source_lead_id IS NOT NULL THEN
    SELECT * INTO v_lead FROM leads
    WHERE id = p_source_lead_id AND tenant_id = v_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'lead_not_found'; END IF;
    IF v_lead.lead_role NOT IN ('buyer','renter') THEN
      RAISE EXCEPTION 'lead_role_not_buyer';
    END IF;
    IF v_price_min IS NULL THEN v_price_min := v_lead.budget_min; END IF;
    IF v_price_max IS NULL THEN v_price_max := v_lead.budget_max; END IF;
    IF v_city IS NULL OR trim(v_city) = '' THEN v_city := v_lead.desired_area; END IF;
  END IF;

  IF p_source_property_id IS NOT NULL THEN
    SELECT * INTO v_prop FROM properties
    WHERE id = p_source_property_id AND tenant_id = v_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;
    IF v_price_min IS NULL THEN v_price_min := v_prop.price; END IF;
    IF v_price_max IS NULL THEN v_price_max := v_prop.price; END IF;
    IF v_rooms IS NULL THEN v_rooms := v_prop.rooms; END IF;
    IF v_city IS NULL OR trim(v_city) = '' THEN v_city := v_prop.city; END IF;
    IF v_ptype IS NULL THEN v_ptype := v_prop.type; END IF;
  END IF;

  INSERT INTO market_board_posts (
    tenant_id, created_by, post_type, region, city, property_type,
    price_min, price_max, rooms, description, source_lead_id, source_property_id
  ) VALUES (
    v_tenant_id, auth.uid(), p_post_type, p_region,
    nullif(left(coalesce(trim(v_city),''), 80), ''),
    v_ptype, v_price_min, v_price_max, v_rooms,
    nullif(left(coalesce(p_description,''), 500), ''),
    p_source_lead_id, p_source_property_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.publish_market_post(text,text,text,text,numeric,numeric,numeric,text,uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.publish_market_post(text,text,text,text,numeric,numeric,numeric,text,uuid,uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.publish_market_post(text,text,text,text,numeric,numeric,numeric,text,uuid,uuid) TO authenticated;

-- ── list_market_board(): the open board, contact info visible immediately ──
CREATE OR REPLACE FUNCTION public.list_market_board(
  p_post_type text DEFAULT NULL, p_region text DEFAULT NULL
) RETURNS TABLE (
  id uuid, post_type text, region text, city text, property_type text,
  price_min numeric, price_max numeric, rooms numeric, description text,
  poster_name text, poster_phone text, created_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_industry  text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  SELECT t2.industry INTO v_industry FROM tenants t2 WHERE t2.id = v_tenant_id;
  IF coalesce(v_industry, 'other') <> 'realestate' THEN
    RAISE EXCEPTION 'vertical_not_supported';
  END IF;

  -- Lazy expiry sweep
  UPDATE market_board_posts SET status = 'expired'
  WHERE status = 'open' AND expires_at < now();

  RETURN QUERY
  SELECT p.id, p.post_type, p.region, p.city, p.property_type,
         p.price_min, p.price_max, p.rooms, p.description,
         coalesce(t.name, 'משתמש PLTO'), coalesce(t.phone, ''),
         p.created_at
  FROM market_board_posts p
  JOIN tenants t ON t.id = p.tenant_id
  WHERE p.status = 'open'
    AND p.tenant_id <> v_tenant_id
    AND (p_post_type IS NULL OR p.post_type = p_post_type)
    AND (p_region    IS NULL OR p.region = p_region)
  ORDER BY p.created_at DESC
  LIMIT 100;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_market_board(text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_market_board(text,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.list_market_board(text,text) TO authenticated;

-- ── list_my_market_posts() ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_my_market_posts()
RETURNS TABLE (
  id uuid, post_type text, region text, city text, property_type text,
  price_min numeric, price_max numeric, rooms numeric, description text,
  status text, created_at timestamptz, expires_at timestamptz
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT p.id, p.post_type, p.region, p.city, p.property_type,
         p.price_min, p.price_max, p.rooms, p.description,
         p.status, p.created_at, p.expires_at
  FROM market_board_posts p
  WHERE p.tenant_id = get_my_tenant_id()
  ORDER BY p.created_at DESC
  LIMIT 50;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_my_market_posts() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_my_market_posts() FROM anon;
GRANT  EXECUTE ON FUNCTION public.list_my_market_posts() TO authenticated;

-- ── close_market_post(): owner only ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.close_market_post(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  UPDATE market_board_posts SET status = 'closed'
  WHERE id = p_id AND tenant_id = v_tenant_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'post_not_found'; END IF;

  RETURN jsonb_build_object('ok', true);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.close_market_post(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.close_market_post(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.close_market_post(uuid) TO authenticated;
