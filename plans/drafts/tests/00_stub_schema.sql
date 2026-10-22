-- סכמת בדיקה מקומית בלבד, מדמה את החלקים הרלוונטיים של ה-DB החי. לא רצה בשום סביבה אחרת.
DO $$ BEGIN
  CREATE ROLE anon NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE authenticated NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE service_role NOLOGIN BYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
GRANT USAGE ON SCHEMA public, auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

CREATE TABLE public.tenants (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 text NOT NULL,
  slug                 text UNIQUE NOT NULL,
  plan                 text NOT NULL DEFAULT 'trial' CHECK (plan IN ('trial','basic','pro','premium','lifetime','cancelled')),
  trial_ends_at        timestamptz,
  marketing_addon      boolean NOT NULL DEFAULT false,
  stripe_customer_id   text,
  industry             text DEFAULT 'other' CHECK (industry IN ('realestate','realestate_lawyer','interior','other')),
  onboarding_completed boolean NOT NULL DEFAULT false,
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.agent_users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  auth_user_id uuid UNIQUE,
  role         text NOT NULL CHECK (role IN ('owner','admin','agent','viewer'))
);
CREATE TABLE public.leads      (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES public.tenants(id));
CREATE TABLE public.properties (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES public.tenants(id));

CREATE FUNCTION public.get_my_tenant_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS
$$ SELECT tenant_id FROM agent_users WHERE auth_user_id = auth.uid() LIMIT 1 $$;

-- הרשאות כמו בחי: ל-authenticated הכל על הטבלה (ברירת המחדל של Supabase), ועוד מענק עמודה מ-029
GRANT ALL ON public.tenants, public.agent_users, public.leads, public.properties TO authenticated, service_role;
GRANT UPDATE (onboarding_completed) ON public.tenants TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_tenant_id() TO authenticated;

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon no access" ON public.tenants FOR ALL TO anon USING (false);
CREATE POLICY "service role full access" ON public.tenants FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "agents read own tenant" ON public.tenants FOR SELECT TO authenticated USING (id = public.get_my_tenant_id());

-- טריגר updated_at (SECURITY INVOKER, כמו בחי) וטריגר על plan (SECURITY DEFINER, כמו בחי)
CREATE FUNCTION public.update_updated_at_column() RETURNS trigger LANGUAGE plpgsql AS
$$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
CREATE TRIGGER tenants_updated_at BEFORE UPDATE ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TABLE public.plan_change_log (tenant_id uuid, old_plan text, new_plan text);
CREATE FUNCTION public._plan_trigger() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS
$$ BEGIN INSERT INTO plan_change_log VALUES (NEW.id, OLD.plan, NEW.plan); RETURN NEW; END $$;
CREATE TRIGGER referral_conversion_reward_trg AFTER UPDATE OF plan ON public.tenants FOR EACH ROW
  WHEN (OLD.plan IS DISTINCT FROM NEW.plan) EXECUTE FUNCTION public._plan_trigger();

-- שתי פונקציות קיימות מהחי, בגרסה מצומצמת, כדי לוודא ש-REVOKE לא שובר אותן
CREATE FUNCTION public.update_tenant_profile(p_name text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS
$$ DECLARE v_tenant uuid; v_role text; BEGIN
  SELECT tenant_id, role INTO v_tenant, v_role FROM agent_users WHERE auth_user_id = auth.uid() LIMIT 1;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'no tenant for current user'; END IF;
  IF v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'insufficient permissions'; END IF;
  UPDATE tenants SET name = trim(p_name) WHERE id = v_tenant;
END $$;
CREATE FUNCTION public.admin_set_plan(p_tenant uuid, p_plan text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS
$$ BEGIN UPDATE tenants SET plan = p_plan WHERE id = p_tenant; END $$;
REVOKE ALL ON FUNCTION public.update_tenant_profile(text), public.admin_set_plan(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_tenant_profile(text), public.admin_set_plan(uuid, text) TO authenticated;

-- עסקים ומשתמשים לבדיקה
INSERT INTO public.tenants (id, name, slug, plan, industry, onboarding_completed) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'A other',        'a',  'trial',    'other',             false),
  ('b0000000-0000-0000-0000-000000000002', 'B realestate',   'b',  'lifetime', 'realestate',        true),
  ('c0000000-0000-0000-0000-000000000003', 'L lawyer data',  'l',  'trial',    'realestate_lawyer', true),
  ('d0000000-0000-0000-0000-000000000004', 'M lawyer empty', 'm',  'trial',    'realestate_lawyer', false);
INSERT INTO public.agent_users (tenant_id, auth_user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('a0000000-0000-0000-0000-000000000001', '12121212-1212-1212-1212-121212121212', 'agent'),
  ('a0000000-0000-0000-0000-000000000001', '13131313-1313-1313-1313-131313131313', 'viewer'),
  ('a0000000-0000-0000-0000-000000000001', '14141414-1414-1414-1414-141414141414', 'admin'),
  ('b0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'owner'),
  ('c0000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'owner'),
  ('d0000000-0000-0000-0000-000000000004', '44444444-4444-4444-4444-444444444444', 'owner');
INSERT INTO public.leads (tenant_id) VALUES ('c0000000-0000-0000-0000-000000000003');

-- עזרי בדיקה: הרצת פקודה כמשתמש מסוים, והחזרת הערך או השגיאה
CREATE SCHEMA t;
GRANT USAGE ON SCHEMA t TO PUBLIC;
-- מחזיר 'ok:<ערך>' או 'err:<הודעה>'. uid ריק פירושו בלי JWT.
CREATE FUNCTION t.run(p_role text, p_uid uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN '' ELSE json_build_object('sub', p_uid::text, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql INTO v;
    RESET ROLE;
    RETURN 'ok:' || coalesce(v, '');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RETURN 'err:' || SQLERRM;
  END;
END $$;
CREATE FUNCTION t.eq(p_actual text, p_expected text, p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'נכשל: % | צפוי [%] התקבל [%]', p_name, p_expected, p_actual;
  END IF;
  RAISE NOTICE 'עבר: %', p_name;
END $$;
CREATE FUNCTION t.like(p_actual text, p_pattern text, p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS NULL OR p_actual NOT LIKE p_pattern THEN
    RAISE EXCEPTION 'נכשל: % | תבנית [%] התקבל [%]', p_name, p_pattern, p_actual;
  END IF;
  RAISE NOTICE 'עבר: %', p_name;
END $$;
