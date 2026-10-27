-- Migration 130 (טיוטה, לא הורצה): שמירת התקדמות המשחק (XP, דרגה, הישגים) בשרת, לכל משתמש.
--
-- רקע
--   עד היום מצב המשחק נשמר רק ב-localStorage, במפתח אחד שלא תלוי במשתמש (plto_gamify_v2).
--   בטלפון חדש או אחרי ניקוי הדפדפן ההתקדמות נמחקת, ושני משתמשים באותו דפדפן חולקו XP.
--   קוד הדפדפן עובר למפתח לפי משתמש (בלי DB). המיגרציה הזו מוסיפה גיבוי בשרת, כדי
--   שההתקדמות תעבור בין מכשירים, ותהיה בסיס לצוות ולמורה בעתיד.
--
-- גבולות
--   - הגישה רק דרך שתי פונקציות RPC. לטבלה אין מדיניות RLS לתפקידי הלקוח, ולכן אין
--     קריאה או כתיבה ישירה. הפונקציות מזהות את המשתמש לפי auth.uid() בלבד, בלי פרמטר
--     של משתמש או עסק, ולכן אי אפשר לקרוא או לכתוב התקדמות של משתמש אחר.
--   - הנתונים מחושבים בדפדפן ואינם מקור אמת. אין להם ערך כספי (הפרסים הם ערכות תוכן כתובות).
--     אין להשתמש בהם להרשאה, לחיוב או לדירוג תחרותי בלי מנגנון חישוב בשרת.
--   - אותה בדיקת גישה של העסק כמו בשאר הטבלאות (tenant_access_active).
--
-- התנהגות הדפדפן בלי המיגרציה: הקריאה נכשלת עם PGRST202, ההתקדמות נשארת מקומית כמו היום.

CREATE TABLE IF NOT EXISTS public.agent_progress (
  agent_id   uuid PRIMARY KEY REFERENCES public.agent_users(id) ON DELETE CASCADE,
  tenant_id  uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  data       jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT agent_progress_data_object CHECK (jsonb_typeof(data) = 'object'),
  CONSTRAINT agent_progress_data_size   CHECK (octet_length(data::text) <= 32768)
);

CREATE INDEX IF NOT EXISTS agent_progress_tenant_idx ON public.agent_progress (tenant_id);

ALTER TABLE public.agent_progress ENABLE ROW LEVEL SECURITY;
-- גישה דרך RPC בלבד: בלי מדיניות ובלי הרשאות טבלה לתפקידי הלקוח
REVOKE ALL ON TABLE public.agent_progress FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_progress()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_agent  uuid;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT coalesce(public.tenant_access_active(), false) THEN
    RAISE EXCEPTION 'tenant_inactive' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_agent
    FROM agent_users
   WHERE auth_user_id = v_uid AND coalesce(is_active, true)
   LIMIT 1;
  IF v_agent IS NULL THEN
    RAISE EXCEPTION 'no agent for current user' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object('data', data, 'updated_at', updated_at) INTO v_result
    FROM agent_progress WHERE agent_id = v_agent;
  RETURN v_result;  -- NULL כשאין עדיין שורה
END;
$$;

CREATE OR REPLACE FUNCTION public.save_my_progress(p_data jsonb)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_agent  uuid;
  v_tenant uuid;
  v_at     timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT coalesce(public.tenant_access_active(), false) THEN
    RAISE EXCEPTION 'tenant_inactive' USING ERRCODE = '42501';
  END IF;

  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' THEN
    RAISE EXCEPTION 'invalid_progress' USING ERRCODE = '22023';
  END IF;
  IF octet_length(p_data::text) > 32768 THEN
    RAISE EXCEPTION 'progress_too_large' USING ERRCODE = '22023';
  END IF;
  -- xp: מספר שלם אי-שלילי וסביר
  IF NOT (p_data ? 'xp') OR jsonb_typeof(p_data->'xp') <> 'number'
     OR (p_data->>'xp') !~ '^[0-9]{1,8}$' THEN
    RAISE EXCEPTION 'invalid_xp' USING ERRCODE = '22023';
  END IF;

  SELECT id, tenant_id INTO v_agent, v_tenant
    FROM agent_users
   WHERE auth_user_id = v_uid AND coalesce(is_active, true)
   LIMIT 1;
  IF v_agent IS NULL THEN
    RAISE EXCEPTION 'no agent for current user' USING ERRCODE = '42501';
  END IF;

  INSERT INTO agent_progress (agent_id, tenant_id, data, updated_at)
  VALUES (v_agent, v_tenant, p_data, now())
  ON CONFLICT (agent_id) DO UPDATE
    SET data = EXCLUDED.data, tenant_id = EXCLUDED.tenant_id, updated_at = now()
  RETURNING updated_at INTO v_at;
  RETURN v_at;
END;
$$;

-- ברירת המחדל ב-Supabase נותנת EXECUTE ל-anon ול-authenticated, ולכן REVOKE מפורש
REVOKE ALL ON FUNCTION public.get_my_progress()        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_my_progress(jsonb)  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_progress()       TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_my_progress(jsonb) TO authenticated;

-- בדיקות אחרי הרצה (קריאה בלבד):
--   SELECT relrowsecurity FROM pg_class WHERE oid = 'public.agent_progress'::regclass;       -- true
--   SELECT grantee, privilege_type FROM information_schema.role_table_grants
--    WHERE table_name = 'agent_progress' AND grantee IN ('anon','authenticated');            -- אין שורות
--   SELECT proname, proacl FROM pg_proc WHERE proname IN ('get_my_progress','save_my_progress');
--                                                     -- authenticated בלבד (ו-postgres, service_role)
--
-- חזרה לאחור:
--   DROP FUNCTION public.save_my_progress(jsonb);
--   DROP FUNCTION public.get_my_progress();
--   DROP TABLE public.agent_progress;
