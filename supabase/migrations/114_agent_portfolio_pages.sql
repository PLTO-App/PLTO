-- Migration 114: Agent Portfolio Pages ("כרטיס ביקור דיגיטלי")
--
-- Public, stable, always-live link showing a tenant's currently marketable
-- properties (realestate) / projects (interior) in one place, e.g. for an
-- Instagram bio or email signature. Unlike the existing 'referral_invite'
-- client_pages type, this is NOT AI-generated and NOT frozen at creation —
-- it reads live `properties` rows on every view, so the agent never has to
-- regenerate it after adding/removing a listing.
--
-- Vertical scope, deliberate: realestate + interior only. Excluded on
-- purpose for realestate_lawyer — that vertical's `properties` rows are
-- legal cases (case type/title/description can carry client-identifying or
-- privileged information), and publishing an index of a lawyer's active
-- cases on an unauthenticated public page would be a confidentiality risk
-- entirely unlike sharing a marketable listing. Enforced both at creation
-- and at read time (defense in depth if industry changes after creation).
--
-- Security model mirrors 102/104: RLS enabled, no policies, access only
-- through SECURITY DEFINER RPCs. get_public_portfolio()'s "not found" and
-- "tenant inactive" responses stay byte-identical (same pattern as
-- get_public_page in 102) so a lapsed subscription can't be inferred.
--
-- Side-finding while building this, fixed here because it directly blocks
-- the interior vertical from having anything to show on a portfolio page:
-- `properties_type_check` / `properties_status_check` (005) were never
-- updated when PROPERTY_CONFIG (index.html) grew interior/lawyer-specific
-- type and status options (living_room/kitchen/..., planning/on_hold/...).
-- Saving a project under those verticals fails today with a DB constraint
-- violation — confirmed empirically, 0 properties exist for any tenant on
-- industry interior/realestate_lawyer in the live table. Widened here to
-- cover every value PROPERTY_CONFIG actually offers across all 3 verticals.
ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_type_check;
ALTER TABLE properties ADD CONSTRAINT properties_type_check
  CHECK (type IN (
    'apartment','house','penthouse','villa','commercial','office','land','other',  -- realestate (+ legacy villa/office)
    'living_room','kitchen','bedroom','full_apartment',                            -- interior
    'family','tort','realestate','contract','general'                             -- realestate_lawyer
  ));

ALTER TABLE properties DROP CONSTRAINT IF EXISTS properties_status_check;
ALTER TABLE properties ADD CONSTRAINT properties_status_check
  CHECK (status IN (
    'available','under_offer','sold','rented','off_market','coming_soon',  -- realestate
    'planning','in_progress','completed','on_hold',                        -- interior
    'open'                                                                 -- realestate_lawyer ('in_progress'/'completed'/'on_hold' shared with interior)
  ));

ALTER TABLE client_pages DROP CONSTRAINT IF EXISTS client_pages_page_type_check;
ALTER TABLE client_pages ADD CONSTRAINT client_pages_page_type_check
  CHECK (page_type IN ('referral_invite', 'agent_portfolio'));

-- Portfolio pages don't freeze a CTA at creation (the page IS the content,
-- read live from `properties` on every view) — referral_invite pages still
-- require it via application-level INSERT, this just drops the DB-level
-- NOT NULL so the column can serve both page types.
ALTER TABLE client_pages ALTER COLUMN cta_url DROP NOT NULL;

-- ── get_or_create_my_portfolio_page(): authenticated, one stable slug per tenant ──
CREATE OR REPLACE FUNCTION public.get_or_create_my_portfolio_page()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_industry  text;
  v_name      text;
  v_slug      text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  SELECT industry, name INTO v_industry, v_name FROM tenants WHERE id = v_tenant_id;
  IF v_industry NOT IN ('realestate', 'interior') THEN
    RAISE EXCEPTION 'vertical_not_supported';
  END IF;

  -- Stable link: reuse the existing page if one was already generated for this tenant.
  SELECT slug INTO v_slug FROM client_pages
  WHERE tenant_id = v_tenant_id AND page_type = 'agent_portfolio' AND status = 'published'
  LIMIT 1;

  IF v_slug IS NULL THEN
    INSERT INTO client_pages (tenant_id, page_type, title, status, created_by_user_id)
    VALUES (v_tenant_id, 'agent_portfolio', left(coalesce(v_name, ''), 120), 'published', auth.uid())
    RETURNING slug INTO v_slug;
  END IF;

  RETURN jsonb_build_object('slug', v_slug);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_or_create_my_portfolio_page() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_or_create_my_portfolio_page() TO authenticated;

-- ── get_public_portfolio(): anon-callable, powers portfolio.html ──
CREATE OR REPLACE FUNCTION public.get_public_portfolio(p_slug text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_page     client_pages%ROWTYPE;
  v_industry text;
  v_name     text;
  v_props    jsonb;
BEGIN
  SELECT * INTO v_page FROM client_pages
  WHERE slug = p_slug AND page_type = 'agent_portfolio' AND status = 'published';

  IF NOT FOUND OR NOT public.public_page_tenant_active(v_page.tenant_id) THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT industry, name INTO v_industry, v_name FROM tenants WHERE id = v_page.tenant_id;

  -- Re-check vertical at read time too — a tenant that switched away from
  -- realestate/interior after generating the link must stop exposing it,
  -- same "not found" shape as everything else above.
  IF v_industry NOT IN ('realestate', 'interior') THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  UPDATE client_pages SET view_count = view_count + 1 WHERE id = v_page.id;

  -- "Portfolio" means something different per vertical: for realestate it's
  -- current listings worth a call (available/coming_soon); for interior a
  -- portfolio is a showcase of finished work (completed), not half-done
  -- projects still in planning.
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_props
  FROM (
    SELECT p.title, p.type, p.price, p.area_sqm, p.rooms, p.floor,
           p.address, p.city, p.description, p.image_url, p.virtual_tour_url
    FROM properties p
    WHERE p.tenant_id = v_page.tenant_id
      AND p.status = ANY (CASE v_industry
            WHEN 'realestate' THEN ARRAY['available', 'coming_soon']
            WHEN 'interior'   THEN ARRAY['completed']
            ELSE ARRAY[]::text[]
          END)
    ORDER BY p.created_at DESC
    LIMIT 50
  ) row;

  RETURN jsonb_build_object(
    'available', true,
    'tenant_name', v_name,
    'industry', v_industry,
    'properties', v_props
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_public_portfolio(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_public_portfolio(text) TO anon, authenticated;
