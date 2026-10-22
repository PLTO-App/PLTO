-- Migration 128 (טיוטה, לא הורצה): טבלת הביצועים מתעלמת מלידים שסומנו "לא נסגר".
--
-- "לא נסגר" נשמר כ-leads.status = 'closed_lost' (העמודה והערך כבר קיימים, ובחי כל 27 הלידים 'new').
-- בלי השינוי הזה ליד כזה היה נספר במספר הלידים, באחוז הסגירה ובשווי הפתוח.
-- ההגדרה החיה של הפונקציה זהה למיגרציה 085 (נבדק ב-22.10.2026), והשינוי היחיד הוא תנאי ה-JOIN.
-- חזרה לאחור: להריץ שוב את מיגרציה 085.

CREATE OR REPLACE FUNCTION public.get_agent_leaderboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_agent  agent_users%ROWTYPE;
  v_plan   text;
  v_agents jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;

  SELECT * INTO v_agent FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
  IF v_agent.id IS NULL THEN RAISE EXCEPTION 'no tenant found for caller'; END IF;
  IF v_agent.role NOT IN ('owner','admin') THEN
    RAISE EXCEPTION 'owner or admin required';
  END IF;

  SELECT plan INTO v_plan FROM tenants WHERE id = v_agent.tenant_id;
  IF v_plan NOT IN ('pro','premium','lifetime') THEN
    RAISE EXCEPTION 'plan_upgrade_required';
  END IF;

  WITH stats AS (
    SELECT
      a.id                                                            AS agent_id,
      a.name                                                          AS name,
      a.role                                                          AS role,
      count(l.id)                                                     AS total_leads,
      count(l.id) FILTER (WHERE ps.is_won)                            AS closed_deals,
      CASE WHEN count(l.id) > 0
        THEN round((count(l.id) FILTER (WHERE ps.is_won))::numeric / count(l.id) * 100)
        ELSE 0
      END                                                              AS conversion_rate,
      coalesce(sum(l.budget_max) FILTER (WHERE NOT coalesce(ps.is_terminal,false)), 0) AS active_pipeline_value,
      max(l.updated_at)                                               AS last_activity_at
    FROM agent_users a
    LEFT JOIN leads l           ON l.agent_id = a.id AND l.status <> 'closed_lost'
    LEFT JOIN pipeline_stages ps ON ps.id = l.pipeline_stage_id
    WHERE a.tenant_id = v_agent.tenant_id AND a.is_active = true
    GROUP BY a.id, a.name, a.role
  ),
  ranked AS (
    SELECT stats.*, RANK() OVER (ORDER BY closed_deals DESC, total_leads DESC) AS rank
    FROM stats
  )
  SELECT jsonb_agg(jsonb_build_object(
    'agent_id', agent_id, 'name', name, 'role', role, 'rank', rank,
    'total_leads', total_leads, 'closed_deals', closed_deals,
    'conversion_rate', conversion_rate, 'active_pipeline_value', active_pipeline_value,
    'last_activity_at', last_activity_at
  ) ORDER BY rank, name)
  INTO v_agents
  FROM ranked;

  RETURN jsonb_build_object(
    'plan', v_plan,
    'agent_count', coalesce(jsonb_array_length(v_agents), 0),
    'agents', coalesce(v_agents, '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_agent_leaderboard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_agent_leaderboard() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_agent_leaderboard() TO authenticated;
