-- Fix: create the missing update_tenant_integrations RPC that the
-- settings UI calls when saving Make.com webhook URL / WhatsApp number.
-- Also restore SELECT on make_webhook_url for authenticated users
-- (RLS already limits reads to the user's own tenant row).

CREATE OR REPLACE FUNCTION update_tenant_integrations(
  p_make_webhook_url text DEFAULT NULL,
  p_whatsapp_number  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  SELECT tenant_id INTO v_tenant_id
  FROM agent_users
  WHERE id = auth.uid();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'No tenant found for this user';
  END IF;

  UPDATE tenants SET
    make_webhook_url = COALESCE(p_make_webhook_url, make_webhook_url),
    whatsapp_number  = COALESCE(p_whatsapp_number,  whatsapp_number),
    updated_at       = now()
  WHERE id = v_tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_tenant_integrations(text, text) TO authenticated;

-- Restore SELECT on make_webhook_url (was revoked in migration 019)
GRANT SELECT (make_webhook_url) ON tenants TO authenticated;
