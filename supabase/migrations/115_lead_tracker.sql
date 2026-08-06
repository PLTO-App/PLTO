-- Migration 115: Lead Tracker ("מעקב חי ללקוח")
--
-- Flagship cross-vertical feature: a public, read-only, per-lead link the
-- professional shares with THEIR OWN client, showing the pipeline stage,
-- checklist progress (realestate_lawyer / interior only, reusing the
-- existing CHECKLIST_TEMPLATES data that's already client-safe generic
-- text), and a curated feed of manually-composed updates. The point is to
-- make normally-invisible work (marketing effort, showings, waiting on a
-- third party, supplier research) visible to the client, on the client's
-- own single relationship with their own professional — not a cross-tenant
-- aggregation, not multi-party collaboration, not automated outreach.
--
-- Security model mirrors 102/104/114: RLS enabled, no policies, access only
-- through SECURITY DEFINER RPCs. get_public_lead_tracker()'s "not found" and
-- "tenant inactive" responses stay byte-identical (same pattern as
-- get_public_page/get_public_portfolio) so a lapsed subscription can't be
-- inferred by a visiting client.
--
-- Deliberately NOT reusing `activities.content` for the update feed: that
-- field carries free-text internal shorthand (commission notes, candid
-- impressions of the client) never meant for the client's own eyes. Updates
-- shown on the tracker are a separate, explicitly-composed table — the act
-- of writing one IS the opt-in, no extra "visible to client" toggle needed.
--
-- Deferred to a later migration (documented in CLAUDE.md, not built here):
-- linking `properties` to a seller-side lead so buyer-side showings
-- (PropertyShown) automatically count toward the seller's tracker. For now
-- the realestate showings story is told through the same manual updates
-- mechanism as every other vertical.

-- ── lead_tracker_updates: curated, client-facing manual log ──
CREATE TABLE IF NOT EXISTS public.lead_tracker_updates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  lead_id            uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  created_by_user_id uuid,
  title              text NOT NULL,
  detail             text,
  icon               text,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lead_tracker_updates_lead ON public.lead_tracker_updates(lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lead_tracker_updates_tenant ON public.lead_tracker_updates(tenant_id);

ALTER TABLE public.lead_tracker_updates ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: all access via SECURITY DEFINER RPCs below.

-- ── client_pages: extend for the new page_type ──
ALTER TABLE client_pages ADD COLUMN IF NOT EXISTS lead_id uuid REFERENCES leads(id) ON DELETE CASCADE;

ALTER TABLE client_pages DROP CONSTRAINT IF EXISTS client_pages_page_type_check;
ALTER TABLE client_pages ADD CONSTRAINT client_pages_page_type_check
  CHECK (page_type IN ('referral_invite', 'agent_portfolio', 'lead_tracker'));

-- Lead tracker pages, like portfolio pages, read live data on every view and
-- don't freeze a CTA at creation time.
ALTER TABLE client_pages ALTER COLUMN cta_url DROP NOT NULL;

-- ── get_or_create_lead_tracker_link(): authenticated, one stable slug per lead ──
CREATE OR REPLACE FUNCTION public.get_or_create_lead_tracker_link(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_slug      text;
  v_status    text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  IF NOT EXISTS (SELECT 1 FROM leads WHERE id = p_lead_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'lead not found';
  END IF;

  -- Deliberately NOT filtered by status: an archived (paused) link must stay
  -- the SAME row/slug when the agent reopens this modal, not spawn a second
  -- one. Reactivation is an explicit separate action (set_lead_tracker_status),
  -- never an implicit side-effect of get-or-create.
  SELECT slug, status INTO v_slug, v_status FROM client_pages
  WHERE tenant_id = v_tenant_id AND page_type = 'lead_tracker' AND lead_id = p_lead_id
  LIMIT 1;

  IF v_slug IS NULL THEN
    INSERT INTO client_pages (tenant_id, page_type, lead_id, status, created_by_user_id)
    VALUES (v_tenant_id, 'lead_tracker', p_lead_id, 'published', auth.uid())
    RETURNING slug, status INTO v_slug, v_status;
  END IF;

  RETURN jsonb_build_object('slug', v_slug, 'status', v_status);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_or_create_lead_tracker_link(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_or_create_lead_tracker_link(uuid) TO authenticated;

-- ── set_lead_tracker_status(): pause/resume an existing link ──
CREATE OR REPLACE FUNCTION public.set_lead_tracker_status(p_lead_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  IF p_status NOT IN ('published', 'archived') THEN RAISE EXCEPTION 'invalid status'; END IF;

  UPDATE client_pages SET status = p_status, updated_at = now()
  WHERE tenant_id = v_tenant_id AND page_type = 'lead_tracker' AND lead_id = p_lead_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.set_lead_tracker_status(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_lead_tracker_status(uuid, text) TO authenticated;

-- ── add_lead_tracker_update(): authenticated, rate-limited ──
CREATE OR REPLACE FUNCTION public.add_lead_tracker_update(
  p_lead_id uuid, p_title text, p_detail text, p_icon text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_id        uuid;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  IF NOT EXISTS (SELECT 1 FROM leads WHERE id = p_lead_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'lead not found';
  END IF;

  IF coalesce(trim(p_title), '') = '' THEN RAISE EXCEPTION 'title required'; END IF;

  -- 30/day per user: higher than client_pages' 10/day (page/referral creation)
  -- because this is a frequent, low-risk action, not a new public artifact.
  IF (SELECT count(*) FROM lead_tracker_updates u
      WHERE u.created_by_user_id = auth.uid() AND u.created_at > now() - interval '24 hours') >= 30 THEN
    RAISE EXCEPTION 'update_rate_limit';
  END IF;

  INSERT INTO lead_tracker_updates (tenant_id, lead_id, created_by_user_id, title, detail, icon)
  VALUES (v_tenant_id, p_lead_id, auth.uid(), left(trim(p_title), 120), left(nullif(trim(p_detail), ''), 240), left(nullif(trim(p_icon), ''), 8))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.add_lead_tracker_update(uuid, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.add_lead_tracker_update(uuid, text, text, text) TO authenticated;

-- ── list_lead_tracker_updates(): authenticated, in-app management view ──
CREATE OR REPLACE FUNCTION public.list_lead_tracker_updates(p_lead_id uuid)
RETURNS TABLE (id uuid, title text, detail text, icon text, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  RETURN QUERY
  SELECT u.id, u.title, u.detail, u.icon, u.created_at
  FROM lead_tracker_updates u
  WHERE u.lead_id = p_lead_id AND u.tenant_id = v_tenant_id
  ORDER BY u.created_at DESC
  LIMIT 200;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_lead_tracker_updates(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_lead_tracker_updates(uuid) TO authenticated;

-- ── delete_lead_tracker_update(): authenticated, tenant-scoped ──
CREATE OR REPLACE FUNCTION public.delete_lead_tracker_update(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  DELETE FROM lead_tracker_updates WHERE id = p_id AND tenant_id = v_tenant_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.delete_lead_tracker_update(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_lead_tracker_update(uuid) TO authenticated;

-- ── get_public_lead_tracker(): anon-callable, powers track.html ──
CREATE OR REPLACE FUNCTION public.get_public_lead_tracker(p_slug text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_page      client_pages%ROWTYPE;
  v_industry  text;
  v_tname     text;
  v_lead      leads%ROWTYPE;
  v_stages    jsonb;
  v_checklist jsonb;
  v_updates   jsonb;
BEGIN
  SELECT * INTO v_page FROM client_pages
  WHERE slug = p_slug AND page_type = 'lead_tracker' AND status = 'published';

  IF NOT FOUND OR NOT public.public_page_tenant_active(v_page.tenant_id) THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT * INTO v_lead FROM leads WHERE id = v_page.lead_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('available', false);
  END IF;

  SELECT industry, name INTO v_industry, v_tname FROM tenants WHERE id = v_page.tenant_id;

  UPDATE client_pages SET view_count = view_count + 1 WHERE id = v_page.id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'color', s.color,
           'order_idx', s.order_idx, 'is_won', s.is_won
         ) ORDER BY s.order_idx), '[]'::jsonb)
  INTO v_stages
  FROM pipeline_stages s
  WHERE s.tenant_id = v_page.tenant_id;

  -- Checklist: only for verticals that have a template (realestate_lawyer,
  -- interior). Labels come from a fixed, tenant-agnostic template mirrored
  -- from index.html's CHECKLIST_TEMPLATES, already generic client-safe text.
  v_checklist := CASE v_industry
    WHEN 'realestate_lawyer' THEN jsonb_build_array(
      jsonb_build_object('key','client_id','label','זיהוי וייפוי כוח מהלקוח'),
      jsonb_build_object('key','docs_gathered','label','איסוף מסמכים ואסמכתאות'),
      jsonb_build_object('key','initial_review','label','בדיקה וניתוח משפטי ראשוני'),
      jsonb_build_object('key','draft_ready','label','הכנת טיוטת מסמך / כתב טענות'),
      jsonb_build_object('key','client_approval','label','אישור הלקוח לתוכן הסופי'),
      jsonb_build_object('key','final_signed','label','חתימה / הגשה סופית')
    )
    WHEN 'interior' THEN jsonb_build_array(
      jsonb_build_object('key','renderings','label','הדמיות ואישור קונספט'),
      jsonb_build_object('key','materials','label','בחירת חומרים וריהוט'),
      jsonb_build_object('key','budget_lock','label','סגירת תקציב מול הלקוח'),
      jsonb_build_object('key','execution','label','ביצוע בשטח'),
      jsonb_build_object('key','handover','label','מסירת הפרויקט')
    )
    ELSE '[]'::jsonb
  END;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'title', u.title, 'detail', u.detail, 'icon', u.icon, 'created_at', u.created_at
         ) ORDER BY u.created_at DESC), '[]'::jsonb)
  INTO v_updates
  FROM lead_tracker_updates u
  WHERE u.lead_id = v_page.lead_id
  LIMIT 100;

  RETURN jsonb_build_object(
    'available', true,
    'tenant_name', v_tname,
    'lead_name', v_lead.name,
    'industry', v_industry,
    'current_stage_id', v_lead.pipeline_stage_id,
    'stages', v_stages,
    'checklist_template', v_checklist,
    'checklist_state', coalesce(v_lead.checklist, '{}'::jsonb),
    'updates', v_updates
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_public_lead_tracker(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_public_lead_tracker(text) TO anon, authenticated;
