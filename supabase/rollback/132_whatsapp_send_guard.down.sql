-- חזרה לאחור של מיגרציה 132. מחזיר את update_tenant_integrations לגוף שהיה בחי ב-28.10.2026
-- (בלי בדיקת תפקיד ובלי אימות מספר), ומוחק את יומן השליחות והפונקציות החדשות.
-- יש לוודא קודם ש-WHATSAPP_ENABLED כבוי, כי בלי ההגנות הפונקציה ב-Edge המקורית אינה מוגבלת.
-- מוחק את יומן השליחות (ספירה יומית בלבד, בלי מספרים ובלי תוכן).
-- הקובץ הזה אינו בתיקיית migrations, ולכן לא יורץ אוטומטית.

CREATE OR REPLACE FUNCTION public.update_tenant_integrations(p_make_webhook_url text DEFAULT NULL::text, p_whatsapp_number text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;

  SELECT tenant_id INTO v_tenant_id
  FROM agent_users
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'No tenant found for this user';
  END IF;

  UPDATE tenants SET
    make_webhook_url = COALESCE(p_make_webhook_url, make_webhook_url),
    whatsapp_number  = COALESCE(p_whatsapp_number,  whatsapp_number),
    updated_at       = now()
  WHERE id = v_tenant_id;
END;
$function$;

DROP FUNCTION IF EXISTS public.reserve_whatsapp_send(uuid, text);
DROP TABLE IF EXISTS public.whatsapp_send_log;
DROP FUNCTION IF EXISTS public.whatsapp_limits();
DROP FUNCTION IF EXISTS public.normalize_il_mobile(text);
