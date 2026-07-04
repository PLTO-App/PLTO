-- community_jokes: user-submitted jokes for the daily joke rotation.
-- Approved jokes earn the submitter 200 XP (client-side, pulled on login).

CREATE TABLE IF NOT EXISTS public.community_jokes (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  submitted_by    UUID        NOT NULL,
  tenant_id       UUID        REFERENCES public.tenants(id) ON DELETE SET NULL,
  submitter_name  TEXT        NOT NULL DEFAULT '',
  joke_text       TEXT        NOT NULL
                              CHECK (char_length(trim(joke_text)) >= 20
                                 AND char_length(joke_text) <= 1200),
  category        TEXT        NOT NULL DEFAULT 'general'
                              CHECK (category IN
                                ('realestate','realestate_lawyer','interior','general')),
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','approved','rejected')),
  xp_awarded      BOOLEAN     NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cj_pending_xp
  ON community_jokes(submitted_by)
  WHERE status = 'approved' AND xp_awarded = false;

CREATE INDEX IF NOT EXISTS idx_cj_approved
  ON community_jokes(approved_at DESC)
  WHERE status = 'approved';

ALTER TABLE public.community_jokes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated insert own joke"
  ON public.community_jokes FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid());

CREATE POLICY "anon read approved jokes"
  ON public.community_jokes FOR SELECT TO anon, authenticated
  USING (status = 'approved');

CREATE POLICY "authenticated read own jokes"
  ON public.community_jokes FOR SELECT TO authenticated
  USING (submitted_by = auth.uid());

-- ── submit_community_joke ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_community_joke(
  p_text     TEXT,
  p_category TEXT DEFAULT 'general'
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_tid     UUID;
  v_name    TEXT;
  v_today   INT;
  v_joke_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT COUNT(*) INTO v_today
  FROM community_jokes
  WHERE submitted_by = v_uid AND created_at >= CURRENT_DATE;

  IF v_today >= 3 THEN
    RETURN json_build_object('ok', false, 'reason', 'daily_limit');
  END IF;

  IF p_category NOT IN ('realestate','realestate_lawyer','interior','general') THEN
    p_category := 'general';
  END IF;

  SELECT a.tenant_id, a.name
  INTO v_tid, v_name
  FROM public.agents a
  WHERE a.auth_user_id = v_uid
  LIMIT 1;

  INSERT INTO public.community_jokes
    (submitted_by, tenant_id, submitter_name, joke_text, category)
  VALUES (v_uid, v_tid, COALESCE(v_name,''), p_text, p_category)
  RETURNING id INTO v_joke_id;

  RETURN json_build_object('ok', true, 'id', v_joke_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_community_joke(TEXT,TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_community_joke(TEXT,TEXT) TO authenticated;

-- ── list_approved_jokes ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_approved_jokes()
RETURNS TABLE (
  id             UUID,
  joke_text      TEXT,
  category       TEXT,
  submitter_name TEXT,
  approved_at    TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$
  SELECT id, joke_text, category, submitter_name, approved_at
  FROM community_jokes
  WHERE status = 'approved'
  ORDER BY approved_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.list_approved_jokes() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_approved_jokes() TO anon, authenticated;

-- ── pull_joke_approval_xp ─────────────────────────────────────────────────
-- Called on login: returns count of newly-approved jokes for the caller.
-- Client awards 200 XP per returned count.
CREATE OR REPLACE FUNCTION public.pull_joke_approval_xp()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_count INT;
BEGIN
  IF v_uid IS NULL THEN RETURN 0; END IF;

  UPDATE community_jokes
  SET xp_awarded = true
  WHERE submitted_by = v_uid
    AND status = 'approved'
    AND xp_awarded = false;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.pull_joke_approval_xp() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.pull_joke_approval_xp() TO authenticated;

-- ── admin_list_community_jokes ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_community_jokes(p_pin TEXT)
RETURNS TABLE (
  id             UUID,
  joke_text      TEXT,
  category       TEXT,
  submitter_name TEXT,
  status         TEXT,
  xp_awarded     BOOLEAN,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT (SELECT public.verify_admin_pin(p_pin)) THEN
    RAISE EXCEPTION 'invalid_pin';
  END IF;
  RETURN QUERY
    SELECT cj.id, cj.joke_text, cj.category, cj.submitter_name,
           cj.status, cj.xp_awarded, cj.created_at
    FROM community_jokes cj
    ORDER BY
      CASE cj.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
      cj.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_community_jokes(TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.admin_list_community_jokes(TEXT) TO authenticated;

-- ── admin_approve_community_joke ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_approve_community_joke(
  p_pin     TEXT,
  p_joke_id UUID
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT (SELECT public.verify_admin_pin(p_pin)) THEN
    RETURN json_build_object('ok', false, 'reason', 'invalid_pin');
  END IF;

  UPDATE community_jokes
  SET status = 'approved', approved_at = now()
  WHERE id = p_joke_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'reason', 'not_found_or_already_processed');
  END IF;

  RETURN json_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_approve_community_joke(TEXT,UUID)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.admin_approve_community_joke(TEXT,UUID) TO authenticated;

-- ── admin_reject_community_joke ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reject_community_joke(
  p_pin     TEXT,
  p_joke_id UUID
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT (SELECT public.verify_admin_pin(p_pin)) THEN
    RETURN json_build_object('ok', false, 'reason', 'invalid_pin');
  END IF;

  UPDATE community_jokes
  SET status = 'rejected'
  WHERE id = p_joke_id AND status = 'pending';

  RETURN json_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_reject_community_joke(TEXT,UUID)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.admin_reject_community_joke(TEXT,UUID) TO authenticated;
