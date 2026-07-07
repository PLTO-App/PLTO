-- Migration 073: token-based agent invite links
-- Allows agency owners to generate a shareable URL (?ainvite=<32hex>)
-- that lets a new agent join the tenant without a pre-registered email.
-- The token is single-use, 30-day expiry, 128-bit random (unguessable).

-- 1. Make email nullable (token-based invites have no pre-known email)
ALTER TABLE agent_invites ALTER COLUMN email DROP NOT NULL;

-- 2. Add invite_token column
ALTER TABLE agent_invites ADD COLUMN IF NOT EXISTS invite_token text UNIQUE;

-- 3. Recreate email index to exclude NULL emails
DROP INDEX IF EXISTS agent_invites_email_pending_idx;
CREATE INDEX agent_invites_email_pending_idx
  ON agent_invites (lower(email))
  WHERE status = 'pending' AND email IS NOT NULL;

-- 4. Index for fast token lookup
CREATE INDEX IF NOT EXISTS agent_invites_token_idx
  ON agent_invites(invite_token)
  WHERE invite_token IS NOT NULL;

-- ────────────────────────────────────────────────────────────────
-- RPC: create_invite_link — owner/admin generates a shareable link
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_invite_link(p_role text DEFAULT 'agent')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_agent     agent_users%ROWTYPE;
  v_plan      text;
  v_seats     jsonb;
  v_max       int;
  v_current   int;
  v_token     text := encode(gen_random_bytes(16), 'hex');
  v_invite_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  IF p_role NOT IN ('admin','agent','viewer') THEN RAISE EXCEPTION 'invalid role'; END IF;

  SELECT * INTO v_agent FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
  IF v_agent.id IS NULL THEN RAISE EXCEPTION 'no tenant found for caller'; END IF;
  IF v_agent.role NOT IN ('owner','admin') THEN
    RAISE EXCEPTION 'only the owner or an admin can create invite links';
  END IF;

  SELECT plan INTO v_plan FROM tenants WHERE id = v_agent.tenant_id;
  v_seats  := public._seat_config(v_plan);
  v_max    := (v_seats->>'max')::int;

  SELECT
    (SELECT count(*) FROM agent_users  WHERE tenant_id = v_agent.tenant_id AND is_active = true) +
    (SELECT count(*) FROM agent_invites WHERE tenant_id = v_agent.tenant_id AND status = 'pending')
  INTO v_current;

  IF v_current >= v_max THEN
    RAISE EXCEPTION 'seat_limit_reached: % seats is the max for this plan', v_max;
  END IF;

  -- Token-based invite: email is NULL, expiry 30 days (longer than email invite)
  INSERT INTO agent_invites (tenant_id, invite_token, role, invited_by, expires_at)
  VALUES (v_agent.tenant_id, v_token, p_role, v_agent.id, now() + interval '30 days')
  RETURNING id INTO v_invite_id;

  RETURN jsonb_build_object('token', v_token, 'invite_id', v_invite_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_invite_link(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_invite_link(text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.create_invite_link(text) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- RPC: get_invite_preview — public (anon) — returns agency info
-- Called before login to show the "Agency X invited you" banner.
-- Returns only public-safe data: agency name and industry.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_invite_preview(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_invite agent_invites%ROWTYPE;
  v_tenant tenants%ROWTYPE;
BEGIN
  IF p_token IS NULL OR length(p_token) <> 32 THEN
    RETURN jsonb_build_object('valid', false);
  END IF;

  SELECT * INTO v_invite
  FROM agent_invites
  WHERE invite_token = p_token AND status = 'pending' AND expires_at > now()
  LIMIT 1;

  IF v_invite.id IS NULL THEN
    RETURN jsonb_build_object('valid', false);
  END IF;

  SELECT * INTO v_tenant FROM tenants WHERE id = v_invite.tenant_id LIMIT 1;

  RETURN jsonb_build_object(
    'valid',        true,
    'agency_name',  v_tenant.name,
    'industry',     v_tenant.industry
  );
END;
$$;

-- Anon access — intentionally public (only exposes agency name + industry)
REVOKE EXECUTE ON FUNCTION public.get_invite_preview(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_invite_preview(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.get_invite_preview(text) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- Update ensure_agent_and_tenant to handle p_ainvite_token
-- Token check runs before email-match check so the recruiting
-- agency always wins over any stale email invite.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_agent_and_tenant(
  p_agency_name    text DEFAULT NULL,
  p_name           text DEFAULT NULL,
  p_ainvite_token  text DEFAULT NULL
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

  -- Token-based invite (priority: the user clicked a specific agency link)
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

      -- Single-use: mark accepted; store the email for record-keeping
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
    -- Token not found / expired → fall through to email check
  END IF;

  -- Email-based invite check (existing logic from migration 053)
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
    INSERT INTO tenants (name, slug, plan, trial_ends_at, billing_email)
    VALUES (v_agency_name, v_slug, 'trial', now() + interval '30 days', v_email)
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
