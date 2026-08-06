-- Migration 116: Lead Tracker Messaging ("תקשורת דו-כיוונית + אנימציית 'חי'")
--
-- Phase 2 on top of migration 115. Two additions, both from a follow-up
-- conversation with the user after Phase 1 shipped:
--
-- 1. Two-way messaging: the client can write a note directly from track.html,
--    the professional sees it (and replies) from inside the app. Both sides
--    now share the same `lead_tracker_updates` feed, distinguished by a new
--    `sender` column, instead of a separate parallel table — keeps the
--    chronological feed unified exactly like a real conversation thread.
--
-- 2. Write-access gate: read access stays exactly as open as it was in 115
--    (anyone holding the `?p=<slug>` link can view, including family members
--    the client forwards it to, that's an intended viral/marketing channel,
--    not a bug). WRITING must be restricted to the actual client the
--    professional is transacting with, not anyone who received a forwarded
--    read link. Solved with a short PIN (`client_pages.write_pin`), shared by
--    the professional with the client OUT OF BAND (separately from the link
--    itself), never returned by the public read RPC, verified only inside
--    the write RPC. This mirrors the exact proportionality already
--    established for the app's own local PIN lock (documented in CLAUDE.md
--    as "local UI only, not a hard security boundary") — the goal here is
--    blocking accidental/unauthorized writes from a forwarded link, not
--    protecting data that isn't already exposed by the read path anyway.
--
-- Security model otherwise unchanged from 115: RLS enabled, no policies,
-- access only through SECURITY DEFINER RPCs.

ALTER TABLE client_pages ADD COLUMN IF NOT EXISTS write_pin text;

ALTER TABLE lead_tracker_updates ADD COLUMN IF NOT EXISTS sender text NOT NULL DEFAULT 'professional'
  CHECK (sender IN ('professional', 'client'));
ALTER TABLE lead_tracker_updates ADD COLUMN IF NOT EXISTS read_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_lead_tracker_updates_unread
  ON public.lead_tracker_updates(lead_id) WHERE sender = 'client' AND read_at IS NULL;

-- ── get_or_create_lead_tracker_link(): also reports current messaging state ──
-- (115's version returned only slug+status; the in-app modal needs to know
-- whether messaging is already on so it doesn't offer to "enable" something
-- already enabled, without a second round trip.)
CREATE OR REPLACE FUNCTION public.get_or_create_lead_tracker_link(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_slug      text;
  v_status    text;
  v_write_pin text;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  IF NOT EXISTS (SELECT 1 FROM leads WHERE id = p_lead_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'lead not found';
  END IF;

  SELECT slug, status, write_pin INTO v_slug, v_status, v_write_pin FROM client_pages
  WHERE tenant_id = v_tenant_id AND page_type = 'lead_tracker' AND lead_id = p_lead_id
  LIMIT 1;

  IF v_slug IS NULL THEN
    INSERT INTO client_pages (tenant_id, page_type, lead_id, status, created_by_user_id)
    VALUES (v_tenant_id, 'lead_tracker', p_lead_id, 'published', auth.uid())
    RETURNING slug, status, write_pin INTO v_slug, v_status, v_write_pin;
  END IF;

  -- write_pin is safe to return here (unlike get_public_lead_tracker, which
  -- never returns it): this RPC is authenticated + tenant-owner-only, it's
  -- the professional viewing their OWN already-set code, not a public leak.
  RETURN jsonb_build_object('slug', v_slug, 'status', v_status, 'messaging_enabled', v_write_pin IS NOT NULL, 'write_pin', v_write_pin);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_or_create_lead_tracker_link(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_or_create_lead_tracker_link(uuid) TO authenticated;

-- ── set_lead_tracker_write_pin(): authenticated, (re)generates a 4-digit PIN ──
-- Regenerating invalidates the old PIN immediately (useful if it leaked).
-- The tracker link must already exist (created via get_or_create_lead_tracker_link
-- in 115) before messaging can be turned on for it.
CREATE OR REPLACE FUNCTION public.set_lead_tracker_write_pin(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
  v_pin       text;
  v_updated   int;
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  UPDATE client_pages SET write_pin = v_pin, updated_at = now()
  WHERE tenant_id = v_tenant_id AND page_type = 'lead_tracker' AND lead_id = p_lead_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'tracker link not found, create it first';
  END IF;

  RETURN jsonb_build_object('pin', v_pin);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.set_lead_tracker_write_pin(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_lead_tracker_write_pin(uuid) TO authenticated;

-- ── disable_lead_tracker_messaging(): authenticated, turns messaging off ──
CREATE OR REPLACE FUNCTION public.disable_lead_tracker_messaging(p_lead_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  UPDATE client_pages SET write_pin = NULL, updated_at = now()
  WHERE tenant_id = v_tenant_id AND page_type = 'lead_tracker' AND lead_id = p_lead_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.disable_lead_tracker_messaging(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.disable_lead_tracker_messaging(uuid) TO authenticated;

-- ── add_lead_tracker_client_message(): anon, PIN-gated, rate-limited ──
-- Deliberately generic failure ('not available') for every rejection reason
-- (bad slug, archived, tenant inactive, messaging disabled, wrong PIN) so a
-- caller probing the endpoint can't distinguish "wrong PIN" from "messaging
-- is off" from "link doesn't exist".
CREATE OR REPLACE FUNCTION public.add_lead_tracker_client_message(
  p_slug text, p_message text, p_pin text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_page  client_pages%ROWTYPE;
BEGIN
  SELECT * INTO v_page FROM client_pages
  WHERE slug = p_slug AND page_type = 'lead_tracker' AND status = 'published';

  IF NOT FOUND
     OR NOT public.public_page_tenant_active(v_page.tenant_id)
     OR v_page.write_pin IS NULL
     OR v_page.write_pin IS DISTINCT FROM p_pin
     OR coalesce(trim(p_message), '') = ''
  THEN
    RETURN jsonb_build_object('ok', false);
  END IF;

  IF (SELECT count(*) FROM lead_tracker_updates u
      WHERE u.lead_id = v_page.lead_id AND u.sender = 'client'
        AND u.created_at > now() - interval '24 hours') >= 20 THEN
    RETURN jsonb_build_object('ok', false);
  END IF;

  INSERT INTO lead_tracker_updates (tenant_id, lead_id, title, sender)
  VALUES (v_page.tenant_id, v_page.lead_id, left(trim(p_message), 500), 'client');

  RETURN jsonb_build_object('ok', true);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.add_lead_tracker_client_message(text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.add_lead_tracker_client_message(text, text, text) TO anon, authenticated;

-- ── list_leads_with_unread_tracker_messages(): authenticated, one bulk query for badges ──
CREATE OR REPLACE FUNCTION public.list_leads_with_unread_tracker_messages()
RETURNS TABLE (lead_id uuid, unread_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT u.lead_id, count(*)
  FROM lead_tracker_updates u
  WHERE u.tenant_id = v_tenant_id AND u.sender = 'client' AND u.read_at IS NULL
  GROUP BY u.lead_id;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_leads_with_unread_tracker_messages() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_leads_with_unread_tracker_messages() TO authenticated;

-- ── mark_lead_tracker_messages_read(): authenticated ──
CREATE OR REPLACE FUNCTION public.mark_lead_tracker_messages_read(p_lead_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  UPDATE lead_tracker_updates SET read_at = now()
  WHERE lead_id = p_lead_id AND tenant_id = v_tenant_id AND sender = 'client' AND read_at IS NULL;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.mark_lead_tracker_messages_read(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_lead_tracker_messages_read(uuid) TO authenticated;

-- ── list_lead_tracker_updates(): now also returns sender, for the in-app modal ──
-- DROP first: changing a TABLE-returning function's column set requires it
-- (Postgres error 42P13, "cannot change return type of existing function"),
-- CREATE OR REPLACE alone isn't enough for a different OUT-parameter row type.
DROP FUNCTION IF EXISTS public.list_lead_tracker_updates(uuid);
CREATE OR REPLACE FUNCTION public.list_lead_tracker_updates(p_lead_id uuid)
RETURNS TABLE (id uuid, title text, detail text, icon text, sender text, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $fn$
DECLARE
  v_tenant_id uuid := get_my_tenant_id();
BEGIN
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;

  RETURN QUERY
  SELECT u.id, u.title, u.detail, u.icon, u.sender, u.created_at
  FROM lead_tracker_updates u
  WHERE u.lead_id = p_lead_id AND u.tenant_id = v_tenant_id
  ORDER BY u.created_at DESC
  LIMIT 200;
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_lead_tracker_updates(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_lead_tracker_updates(uuid) TO authenticated;

-- ── get_public_lead_tracker(): now also returns sender per update + messaging_enabled ──
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
           'title', u.title, 'detail', u.detail, 'icon', u.icon,
           'sender', u.sender, 'created_at', u.created_at
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
    'updates', v_updates,
    'messaging_enabled', v_page.write_pin IS NOT NULL
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.get_public_lead_tracker(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_public_lead_tracker(text) TO anon, authenticated;
