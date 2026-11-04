-- 134: תקופת הניסיון למשתמשים חדשים עולה מ-30 ל-45 ימים (החלטת בעלים, 4.11.2026).
--
-- מה משתנה: רק משך הניסיון של עסק חדש. ensure_agent_and_tenant יוצרת את העסק עם
-- trial_ends_at = now() + 45 days, כלומר הספירה מתחילה ברגע ההרשמה ונמשכת 45 ימים קלנדריים
-- גם בלי כניסה למערכת. ברירת המחדל של העמודה tenants.trial_ends_at מעודכנת לאותו ערך
-- (במסד החי היא נשארה 21 יום מהמיגרציה הישנה 021, וההרשמה תמיד קבעה ערך מפורש).
--
-- מה לא משתנה: עסקים קיימים (אין עדכון לשורות קיימות), מנגנון המנויים, חסימת הגישה בסוף הניסיון,
-- שמירת הנתונים אחרי הניסיון, admin_extend_trial ו-admin_set_plan.
--
-- גוף הפונקציה הוא בדיוק הגוף החי (pg_get_functiondef, נבדק 4.11.2026, זהה ל-109), עם שינוי
-- אחד: interval '30 days' הפך ל-interval '45 days'. החתימה וההרשאות נשארות כמו ב-109.
--
-- ביטול: אותה פונקציה עם interval '30 days', ו-
--   ALTER TABLE public.tenants ALTER COLUMN trial_ends_at SET DEFAULT (now() + interval '21 days');

ALTER TABLE public.tenants ALTER COLUMN trial_ends_at SET DEFAULT (now() + interval '45 days');

CREATE OR REPLACE FUNCTION public.ensure_agent_and_tenant(
  p_agency_name         text DEFAULT NULL,
  p_name                text DEFAULT NULL,
  p_ainvite_token       text DEFAULT NULL,
  p_signup_utm_source   text DEFAULT NULL,
  p_signup_utm_medium   text DEFAULT NULL,
  p_signup_utm_campaign text DEFAULT NULL,
  p_signup_utm_content  text DEFAULT NULL,
  p_signup_utm_term     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid(); v_email text := auth.email();
  v_agent_id uuid; v_tenant_id uuid; v_slug text; v_display_name text; v_agency_name text;
  v_invite agent_invites%ROWTYPE;
  v_joined_tenant_name text; v_joined_industry text;
BEGIN
  IF v_uid IS NULL OR v_email IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;

  SELECT id, tenant_id INTO v_agent_id, v_tenant_id FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
  IF v_agent_id IS NOT NULL THEN
    RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_tenant_id, 'is_new', false);
  END IF;

  v_display_name := coalesce(nullif(trim(p_name), ''), split_part(v_email, '@', 1));

  IF p_ainvite_token IS NOT NULL AND length(p_ainvite_token) = 32 THEN
    SELECT * INTO v_invite
    FROM agent_invites
    WHERE invite_token = p_ainvite_token AND status = 'pending' AND expires_at > now()
    LIMIT 1;

    IF v_invite.id IS NOT NULL THEN
      BEGIN
        INSERT INTO agent_users (tenant_id, auth_user_id, name, email, role)
        VALUES (v_invite.tenant_id, v_uid, v_display_name, v_email, v_invite.role)
        RETURNING id INTO v_agent_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id, tenant_id INTO v_agent_id, v_tenant_id FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
        IF v_agent_id IS NULL THEN RAISE; END IF;
        RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_tenant_id, 'is_new', false);
      END;

      UPDATE agent_invites
        SET status = 'accepted', accepted_at = now(), email = coalesce(email, v_email)
        WHERE id = v_invite.id;

      SELECT name, industry INTO v_joined_tenant_name, v_joined_industry
        FROM tenants WHERE id = v_invite.tenant_id;

      RETURN jsonb_build_object(
        'agent_id',         v_agent_id,
        'tenant_id',        v_invite.tenant_id,
        'is_new',           false,
        'joined_via_token', true,
        'tenant_name',      v_joined_tenant_name,
        'industry',         v_joined_industry
      );
    END IF;
  END IF;

  SELECT * INTO v_invite
  FROM agent_invites
  WHERE lower(email) = lower(v_email) AND status = 'pending' AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_invite.id IS NOT NULL THEN
    BEGIN
      INSERT INTO agent_users (tenant_id, auth_user_id, name, email, role)
      VALUES (v_invite.tenant_id, v_uid, v_display_name, v_email, v_invite.role)
      RETURNING id INTO v_agent_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id, tenant_id INTO v_agent_id, v_tenant_id FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
      IF v_agent_id IS NULL THEN RAISE; END IF;
      RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_tenant_id, 'is_new', false);
    END;

    UPDATE agent_invites SET status = 'accepted', accepted_at = now() WHERE id = v_invite.id;

    RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_invite.tenant_id, 'is_new', false);
  END IF;

  IF public._is_disposable_email(v_email) THEN
    RAISE EXCEPTION 'disposable_email_blocked';
  END IF;

  v_agency_name := coalesce(nullif(trim(p_agency_name), ''), 'הסוכנות של ' || v_display_name);
  v_slug := 'agency-' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);

  BEGIN
    INSERT INTO tenants (
      name, slug, plan, trial_ends_at, billing_email,
      signup_utm_source, signup_utm_medium, signup_utm_campaign, signup_utm_content, signup_utm_term
    )
    VALUES (
      v_agency_name, v_slug, 'trial', now() + interval '45 days', v_email,
      nullif(trim(p_signup_utm_source), ''), nullif(trim(p_signup_utm_medium), ''),
      nullif(trim(p_signup_utm_campaign), ''), nullif(trim(p_signup_utm_content), ''),
      nullif(trim(p_signup_utm_term), '')
    )
    RETURNING id INTO v_tenant_id;
    INSERT INTO pipeline_stages (tenant_id, name, color, order_idx, is_terminal, is_won) VALUES
      (v_tenant_id,'ליד חדש','#94A3B8',1,false,false),
      (v_tenant_id,'בקשר','#3B82F6',2,false,false),
      (v_tenant_id,'ביקור נקבע','#8B5CF6',3,false,false),
      (v_tenant_id,'הצעה הוגשה','#F59E0B',4,false,false),
      (v_tenant_id,'סגירה ✓','#10B981',5,true,true);
    INSERT INTO agent_users (tenant_id, auth_user_id, name, email, role)
    VALUES (v_tenant_id, v_uid, v_display_name, v_email, 'owner')
    RETURNING id INTO v_agent_id;
  EXCEPTION WHEN unique_violation THEN
    SELECT id, tenant_id INTO v_agent_id, v_tenant_id FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
    IF v_agent_id IS NULL THEN RAISE; END IF;
    RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_tenant_id, 'is_new', false);
  END;

  RETURN jsonb_build_object('agent_id', v_agent_id, 'tenant_id', v_tenant_id, 'is_new', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ensure_agent_and_tenant(text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_agent_and_tenant(text, text, text, text, text, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.ensure_agent_and_tenant(text, text, text, text, text, text, text, text) TO authenticated;
