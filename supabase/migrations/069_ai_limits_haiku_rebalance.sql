-- Migration 069: Rebalance AI quotas + switch model routing
-- quicklog/support/general → Haiku (cheaper, sufficient)
-- marketing/motivation → Sonnet (stays, quality matters)
-- motivation: remove progressive cooldown, enforce max 2/day (time-window is client-side)
-- extra seats (agent_invites) always get basic-level limits

CREATE OR REPLACE FUNCTION public.check_and_increment_ai_usage(p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_email text := auth.email();
  v_plan  text;
  v_limit int;
  v_count int;
  v_is_extra_seat boolean := false;
  v_limits constant jsonb := '{
    "trial":    {"general":2,  "marketing":2,  "quicklog":3,  "support":3,  "motivation":1},
    "basic":    {"general":8,  "marketing":5,  "quicklog":10, "support":10, "motivation":2},
    "pro":      {"general":16, "marketing":10, "quicklog":20, "support":20, "motivation":2},
    "premium":  {"general":30, "marketing":18, "quicklog":35, "support":30, "motivation":2},
    "lifetime": {"general":30, "marketing":18, "quicklog":35, "support":30, "motivation":2},
    "cancelled":{"general":0,  "marketing":0,  "quicklog":0,  "support":0,  "motivation":0}
  }';
  -- Extra seats (₪40/month added via agent_invites) always get basic limits
  v_seat_limits constant jsonb := '{"general":8,"marketing":5,"quicklog":10,"support":10,"motivation":2}';
BEGIN
  IF p_type NOT IN ('general','marketing','quicklog','support','motivation') THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'invalid_type');
  END IF;

  -- Internal admins: unlimited
  IF v_email IN ('liders.crm@gmail.com', 'elgrablidudu@gmail.com') THEN
    RETURN jsonb_build_object('allowed', true, 'plan', 'internal', 'admin', true);
  END IF;

  -- Resolve plan + check if this user is an extra seat (not the tenant owner)
  SELECT t.plan,
         (a.role = 'agent' AND EXISTS (
           SELECT 1 FROM agent_invites ai
           WHERE ai.tenant_id = a.tenant_id
             AND ai.email = a.email
             AND ai.status = 'accepted'
         ))
  INTO v_plan, v_is_extra_seat
  FROM agent_users a
  JOIN tenants t ON t.id = a.tenant_id
  WHERE a.auth_user_id = v_uid
  LIMIT 1;

  IF v_plan IS NULL OR v_plan = 'cancelled' THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'no_active_plan');
  END IF;

  -- Extra seats always get basic limits regardless of tenant plan
  IF v_is_extra_seat THEN
    v_limit := COALESCE((v_seat_limits -> p_type)::int, 5);
  ELSE
    v_limit := COALESCE((v_limits -> v_plan -> p_type)::int, 2);
  END IF;

  INSERT INTO ai_usage (user_id, usage_date)
  VALUES (v_uid, CURRENT_DATE)
  ON CONFLICT (user_id, usage_date) DO NOTHING;

  SELECT CASE p_type
    WHEN 'general'    THEN general
    WHEN 'marketing'  THEN marketing
    WHEN 'quicklog'   THEN quicklog
    WHEN 'support'    THEN support
    WHEN 'motivation' THEN motivation
  END
  INTO v_count
  FROM ai_usage
  WHERE user_id = v_uid AND usage_date = CURRENT_DATE
  FOR UPDATE;

  IF v_count >= v_limit THEN
    RETURN jsonb_build_object('allowed', false, 'used', v_count, 'limit', v_limit, 'plan', v_plan);
  END IF;

  -- Motivation: no cooldown enforcement (time-window is handled client-side)
  -- Just enforce daily count limit above.

  UPDATE ai_usage SET
    general    = general    + CASE WHEN p_type = 'general'    THEN 1 ELSE 0 END,
    marketing  = marketing  + CASE WHEN p_type = 'marketing'  THEN 1 ELSE 0 END,
    quicklog   = quicklog   + CASE WHEN p_type = 'quicklog'   THEN 1 ELSE 0 END,
    support    = support    + CASE WHEN p_type = 'support'    THEN 1 ELSE 0 END,
    motivation = motivation + CASE WHEN p_type = 'motivation' THEN 1 ELSE 0 END,
    motivation_last_used_at = CASE WHEN p_type = 'motivation' THEN now() ELSE motivation_last_used_at END
  WHERE user_id = v_uid AND usage_date = CURRENT_DATE;

  RETURN jsonb_build_object('allowed', true, 'used', v_count + 1, 'limit', v_limit, 'plan', v_plan);
END;
$$;
