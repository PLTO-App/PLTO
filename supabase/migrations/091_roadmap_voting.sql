-- Migration 091: roadmap item voting
--
-- roadmap_items (047) already lets users read the public roadmap and submit
-- new ideas via IdeaBox, but had no way to gauge demand on existing items.
-- This adds a lightweight per-agent toggle vote, and seeds the "big, needs
-- real demand before building" ideas identified in the 14/7 feature review
-- so the community can weigh in before we invest engineering time.
--
-- Security model mirrors 061 (lead_referrals): RLS enabled, no policies —
-- all access via SECURITY DEFINER RPCs.

CREATE TABLE IF NOT EXISTS roadmap_item_votes (
  item_id    uuid NOT NULL REFERENCES roadmap_items(id) ON DELETE CASCADE,
  agent_id   uuid NOT NULL REFERENCES agent_users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, agent_id)
);

CREATE INDEX IF NOT EXISTS idx_roadmap_item_votes_item ON roadmap_item_votes(item_id);

ALTER TABLE roadmap_item_votes ENABLE ROW LEVEL SECURITY;

-- ── toggle_roadmap_vote(): adds a vote if none exists, removes it if it does ──
CREATE OR REPLACE FUNCTION public.toggle_roadmap_vote(p_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_agent_id uuid := get_my_agent_id();
  v_voted    boolean;
  v_total    integer;
BEGIN
  IF v_agent_id IS NULL THEN RAISE EXCEPTION 'no agent for current user'; END IF;
  IF NOT EXISTS (SELECT 1 FROM roadmap_items WHERE id = p_item_id AND is_published = true) THEN
    RAISE EXCEPTION 'item not found';
  END IF;

  IF EXISTS (SELECT 1 FROM roadmap_item_votes WHERE item_id = p_item_id AND agent_id = v_agent_id) THEN
    DELETE FROM roadmap_item_votes WHERE item_id = p_item_id AND agent_id = v_agent_id;
    v_voted := false;
  ELSE
    INSERT INTO roadmap_item_votes (item_id, agent_id) VALUES (p_item_id, v_agent_id);
    v_voted := true;
  END IF;

  SELECT count(*) INTO v_total FROM roadmap_item_votes WHERE item_id = p_item_id;
  RETURN jsonb_build_object('voted', v_voted, 'total', v_total);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.toggle_roadmap_vote(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.toggle_roadmap_vote(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.toggle_roadmap_vote(uuid) TO authenticated;

-- ── list_roadmap_items_with_votes(): public read, replaces the raw SELECT
--    the frontend used to run directly against roadmap_items ──
CREATE OR REPLACE FUNCTION public.list_roadmap_items_with_votes()
RETURNS TABLE (
  id uuid, title text, description text, category text, order_idx integer,
  vote_count bigint, my_vote boolean
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT
    ri.id, ri.title, ri.description, ri.category, ri.order_idx,
    count(v.agent_id) AS vote_count,
    coalesce(bool_or(v.agent_id = get_my_agent_id()), false) AS my_vote
  FROM roadmap_items ri
  LEFT JOIN roadmap_item_votes v ON v.item_id = ri.id
  WHERE ri.is_published = true
  GROUP BY ri.id
  ORDER BY count(v.agent_id) DESC, ri.order_idx;
$fn$;
REVOKE EXECUTE ON FUNCTION public.list_roadmap_items_with_votes() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_roadmap_items_with_votes() TO anon;
GRANT  EXECUTE ON FUNCTION public.list_roadmap_items_with_votes() TO authenticated;

-- ── Seed the "heavy" ideas from the 14/7/2026 feature review that need
--    real demand validation before we build them. Digital contract signing
--    for lawyers is already seeded (see 047), not repeated here.
INSERT INTO roadmap_items (title, description, category, source, order_idx) VALUES
  ('לוח השראה אינטראקטיבי למעצבי פנים', 'המעצב מעלה תמונות השראה, הלקוח מסמן אהבתי/לא מתאים ישירות במערכת, בלי לעבור בין וואטסאפ לפינטרסט', 'feature', 'internal', 40),
  ('מחשבון תקציב חי למעצבי פנים', 'בחירת פריטים כמו ריהוט ותאורה עם קישורי ספקים, ותקציב מתעדכן בזמן אמת מול הלקוח', 'feature', 'internal', 50),
  ('סיורים וירטואליים והזמנת יומן ללקוח, לסוכני נדל"ן', 'קישור שהלקוח פותח ובוחר שעה לסיור, שנכנס אוטומטית ליומן הסוכן', 'feature', 'internal', 60),
  ('אישור לקוח דיגיטלי להדמיות, למעצבי פנים', 'שליחת הדמיה ללקוח וקבלת אישור דיגיטלי חתום, במקום סבב אישורים בוואטסאפ', 'feature', 'internal', 70);
