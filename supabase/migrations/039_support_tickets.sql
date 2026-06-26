-- Migration 039: support_tickets — tenant-to-admin support channel

CREATE TABLE IF NOT EXISTS support_tickets (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  tenant_name    text,
  agent_name     text,
  agent_email    text,
  message        text        NOT NULL,
  ai_response    text,
  admin_response text,
  status         text        NOT NULL DEFAULT 'open'
                             CHECK (status IN ('open','ai_handled','admin_replied','resolved')),
  created_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

-- Tenants: insert own tickets
CREATE POLICY "support_insert" ON support_tickets
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = get_my_tenant_id());

-- Tenants: read own tickets
CREATE POLICY "support_select" ON support_tickets
  FOR SELECT TO authenticated
  USING (tenant_id = get_my_tenant_id());

-- Tenants: update own tickets (to save AI response)
CREATE POLICY "support_update" ON support_tickets
  FOR UPDATE TO authenticated
  USING (tenant_id = get_my_tenant_id());

-- Admin RPC: get all support tickets
CREATE OR REPLACE FUNCTION public.get_support_tickets_admin()
RETURNS TABLE (
  id             uuid,
  tenant_id      uuid,
  tenant_name    text,
  agent_name     text,
  agent_email    text,
  message        text,
  ai_response    text,
  admin_response text,
  status         text,
  created_at     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_email text := auth.email();
BEGIN
  IF v_email NOT IN ('liders.crm@gmail.com','elgrablidudu@gmail.com') THEN
    RAISE EXCEPTION 'admin access required';
  END IF;
  RETURN QUERY
  SELECT s.id, s.tenant_id, s.tenant_name, s.agent_name, s.agent_email,
         s.message, s.ai_response, s.admin_response, s.status, s.created_at
  FROM support_tickets s
  ORDER BY s.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_support_tickets_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_support_tickets_admin() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_support_tickets_admin() TO authenticated;

-- Admin RPC: reply to ticket
CREATE OR REPLACE FUNCTION public.admin_reply_support(
  p_ticket_id    uuid,
  p_response     text,
  p_status       text DEFAULT 'admin_replied'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_email text := auth.email();
BEGIN
  IF v_email NOT IN ('liders.crm@gmail.com','elgrablidudu@gmail.com') THEN
    RAISE EXCEPTION 'admin access required';
  END IF;
  UPDATE support_tickets
  SET admin_response = p_response, status = p_status
  WHERE id = p_ticket_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_reply_support(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reply_support(uuid,text,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.admin_reply_support(uuid,text,text) TO authenticated;
