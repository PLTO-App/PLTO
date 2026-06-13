-- ============================================================
-- Security Fix: Revoke PUBLIC EXECUTE on helper SECURITY DEFINER functions
-- ============================================================
-- get_my_tenant_id() and get_my_agent_id() had =X/postgres (PUBLIC) grant,
-- meaning anon could call them via /rest/v1/rpc/ even after explicit anon REVOKE.
-- Removing the PUBLIC grant; keeping explicit grants for authenticated & service_role.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.get_my_tenant_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_agent_id()  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_tenant_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_agent_id()  TO authenticated, service_role;
