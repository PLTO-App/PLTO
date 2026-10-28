-- Migration 132 (טיוטה, לא הורצה): הגנות על שליחת WhatsApp דרך Twilio.
--
-- רקע (סקירה מ-28.10.2026, סעיף 7 ב-plans/sales-game-plan-2026-10-27.md)
--   הפונקציה twilio-whatsapp אישרה יעד לפי מספר שהמשתמש קובע בעצמו (מספר העסק או מספר של ליד),
--   בלי אימות, בלי תקרת שליחה ובלי הגבלה על תוכן. את המספר של העסק שמרה update_tenant_integrations
--   בלי בדיקת פורמט ובלי בדיקת תפקיד.
--
-- מה המיגרציה מוסיפה
--   1. normalize_il_mobile(): נרמול של מספר נייד ישראלי לפורמט +9725XXXXXXXX, או NULL.
--   2. whatsapp_send_log + reserve_whatsapp_send(): שמירת מקום לפני כל שליחה, עם תקרה יומית לעסק
--      ותקרה יומית כללית, והתראה אחת לבעלים כשהספירה הכללית מגיעה ל-80%. היום נספר לפי שעון ישראל.
--      הפונקציה ניתנת להרצה ל-service_role בלבד, ולכן רק פונקציית ה-Edge (אחרי אימות JWT) קוראת לה.
--      משתמש לא יכול לקרוא לה ישירות כדי לבזבז את התקרה הכללית.
--   3. update_tenant_integrations(): שמירת מספר WhatsApp רק לבעלים או אדמין, רק מספר נייד ישראלי תקין,
--      ונשמר בפורמט אחיד. הפרמטר של Make נשאר כמו קודם. הגדרה ריקה מוחקת את המספר.
--
-- ערכי ברירת המחדל של התקרות (whatsapp_limits): 20 ליום לעסק, 200 ליום כללי, התראה ב-80%.
-- הם הצעה לאישור של דוד. לשינוי: מחליפים את whatsapp_limits() במיגרציה נוספת.
--
-- אין כאן שליחה: המיגרציה לא קוראת ל-Twilio ולא מפעילה שירות בתשלום. הפונקציה ב-Edge כבויה כברירת מחדל
-- (WHATSAPP_ENABLED), ואת הסוד מגדיר דוד.
--
-- תלויות: tenants, agent_users. _notify_owner_email (קיימת בחי) משמשת רק להתראה, ובכל כשל היא נבלעת.

CREATE OR REPLACE FUNCTION public.normalize_il_mobile(p text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  d text;
BEGIN
  IF p IS NULL THEN RETURN NULL; END IF;
  d := regexp_replace(p, '[^0-9]', '', 'g');
  IF d LIKE '00972%' THEN d := substr(d, 3); END IF;
  IF d ~ '^05[0-9]{8}$' THEN d := '972' || substr(d, 2); END IF;
  IF d ~ '^9725[0-9]{8}$' THEN RETURN '+' || d; END IF;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_il_mobile(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.normalize_il_mobile(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.whatsapp_limits()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT '{"tenant_daily": 20, "global_daily": 200, "alert_at_percent": 80}'::jsonb;
$$;

REVOKE ALL ON FUNCTION public.whatsapp_limits() FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.whatsapp_send_log (
  id         bigserial PRIMARY KEY,
  tenant_id  uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  agent_id   uuid REFERENCES public.agent_users(id) ON DELETE SET NULL,
  event      text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT whatsapp_send_log_event CHECK (event IN ('new_lead', 'stage_changed', 'deal_closed', 'tasks_due', 'cold_leads', 'test'))
);
-- ביומן אין מספרי טלפון ואין תוכן הודעות, רק עסק, משתמש, סוג אירוע וזמן
CREATE INDEX IF NOT EXISTS whatsapp_send_log_created_idx ON public.whatsapp_send_log (created_at);
CREATE INDEX IF NOT EXISTS whatsapp_send_log_tenant_idx  ON public.whatsapp_send_log (tenant_id, created_at);

ALTER TABLE public.whatsapp_send_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.whatsapp_send_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.whatsapp_send_log_id_seq FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reserve_whatsapp_send(p_auth_user_id uuid, p_event text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_limits      jsonb := public.whatsapp_limits();
  v_tenant_cap  int := (v_limits->>'tenant_daily')::int;
  v_global_cap  int := (v_limits->>'global_daily')::int;
  v_alert_at    int := ceil(v_global_cap * (v_limits->>'alert_at_percent')::numeric / 100.0)::int;
  v_agent_id    uuid;
  v_tenant_id   uuid;
  v_plan        text;
  v_number      text;
  v_day_start   timestamptz := date_trunc('day', now() AT TIME ZONE 'Asia/Jerusalem') AT TIME ZONE 'Asia/Jerusalem';
  v_tenant_n    int;
  v_global_n    int;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_agent');
  END IF;
  IF p_event IS NULL OR p_event NOT IN ('new_lead', 'stage_changed', 'deal_closed', 'tasks_due', 'cold_leads', 'test') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_event');
  END IF;

  SELECT a.id, a.tenant_id INTO v_agent_id, v_tenant_id
    FROM agent_users a
   WHERE a.auth_user_id = p_auth_user_id AND coalesce(a.is_active, true)
   LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_agent');
  END IF;

  SELECT t.plan, t.whatsapp_number INTO v_plan, v_number FROM tenants t WHERE t.id = v_tenant_id;
  -- עסק שבוטל לא שולח. תפוגת ניסיון לא נבדקת כאן, כי בתקופת הצמיחה החינמית היא לא חוסמת (מיגרציה 129)
  IF v_plan IS NULL OR v_plan = 'cancelled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'tenant_blocked');
  END IF;

  IF v_number IS NULL OR btrim(v_number) = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_number');
  END IF;
  v_number := public.normalize_il_mobile(v_number);
  IF v_number IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_number');
  END IF;

  -- נעילה אחת לכל השמירות: הנפח נמוך (עד תקרה יומית כללית), והיא מבטיחה שהתקרה לא נחצית במקביל
  PERFORM pg_advisory_xact_lock(hashtext('plto_whatsapp_reserve'));

  SELECT count(*) FILTER (WHERE tenant_id = v_tenant_id), count(*)
    INTO v_tenant_n, v_global_n
    FROM whatsapp_send_log WHERE created_at >= v_day_start;

  IF v_tenant_n >= v_tenant_cap THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'tenant_daily_limit');
  END IF;
  IF v_global_n >= v_global_cap THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'global_daily_limit');
  END IF;

  INSERT INTO whatsapp_send_log (tenant_id, agent_id, event) VALUES (v_tenant_id, v_agent_id, p_event);
  v_global_n := v_global_n + 1;

  -- התראה אחת ביום לבעלים: הספירה עוברת בדיוק דרך הערך הזה פעם אחת
  IF v_global_n = v_alert_at THEN
    BEGIN
      PERFORM public._notify_owner_email(
        'PLTO: שליחות WhatsApp הגיעו ל-' || (v_limits->>'alert_at_percent') || '% מהתקרה היומית',
        '<p>היום נשלחו ' || v_global_n || ' הודעות WhatsApp מתוך תקרה יומית של ' || v_global_cap || '.</p>'
        || '<p>אחרי התקרה השליחה נעצרת עד מחר. לכיבוי מלא: להגדיר WHATSAPP_ENABLED לערך אחר מ-true.</p>'
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  -- ניקוי הדרגתי של יומן ישן
  IF random() < 0.02 THEN
    DELETE FROM whatsapp_send_log WHERE created_at < now() - interval '35 days';
  END IF;

  RETURN jsonb_build_object('ok', true, 'to', v_number);
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_whatsapp_send(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_whatsapp_send(uuid, text) TO service_role;

-- שמירת המספר: בעלים או אדמין בלבד, ומספר נייד ישראלי תקין בלבד. הגוף המקורי נשמר בהערה בקובץ החזרה לאחור
CREATE OR REPLACE FUNCTION public.update_tenant_integrations(
  p_make_webhook_url text DEFAULT NULL::text,
  p_whatsapp_number  text DEFAULT NULL::text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tenant_id uuid;
  v_role      text;
  v_number    text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;

  SELECT tenant_id, role INTO v_tenant_id, v_role
  FROM agent_users
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'No tenant found for this user';
  END IF;

  IF p_whatsapp_number IS NOT NULL THEN
    IF v_role IS NULL OR v_role NOT IN ('owner', 'admin') THEN
      RAISE EXCEPTION 'insufficient permissions' USING ERRCODE = '42501';
    END IF;
    IF btrim(p_whatsapp_number) = '' THEN
      v_number := NULL;
    ELSE
      v_number := public.normalize_il_mobile(p_whatsapp_number);
      IF v_number IS NULL THEN
        RAISE EXCEPTION 'invalid_whatsapp_number' USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  UPDATE tenants SET
    make_webhook_url = COALESCE(p_make_webhook_url, make_webhook_url),
    whatsapp_number  = CASE WHEN p_whatsapp_number IS NULL THEN whatsapp_number ELSE v_number END,
    updated_at       = now()
  WHERE id = v_tenant_id;
END;
$function$;

-- בדיקות אחרי הרצה (קריאה בלבד), בנוסף ל-supabase/tests/verify-129-131.sql (שורות 132_):
--   SELECT public.normalize_il_mobile('050-123-4567');                    -- +972501234567
--   SELECT relrowsecurity FROM pg_class WHERE oid = 'public.whatsapp_send_log'::regclass;   -- true
--   SELECT proname, proacl FROM pg_proc WHERE proname = 'reserve_whatsapp_send';           -- service_role בלבד
--
-- חזרה לאחור: supabase/rollback/132_whatsapp_send_guard.down.sql
