-- Migration 121: remove a stray FLYP function and tighten a trigger function
--
-- 1. public.reorder_stops(uuid, uuid[])
--    A courier/delivery (FLYP) function was applied to this project by mistake
--    (live migration 20260820113746 "reorder_stops_rpc", with no file in this
--    repo). It reads public.work_days and public.stops, which do not exist in
--    the CRM schema, so it can only fail. Nothing in this database depends on
--    it (no views, triggers, cron jobs or other functions), the repo never
--    references it, and it was executable by anon/authenticated through
--    /rest/v1/rpc. The FLYP project (PLTO-Delivery) has the work_days and
--    stops tables but no reorder_stops function, so FLYP needs it applied
--    there separately, from the FLYP repo.
--
-- 2. public._notify_owner_new_tenant()
--    It is only the body of the BEFORE INSERT trigger trg_notify_owner_new_tenant
--    on public.tenants. A trigger function does not need EXECUTE for the role
--    that fires it (EXECUTE is checked once, at CREATE TRIGGER), so the default
--    grants to PUBLIC/anon/authenticated are not needed and only exposed it as
--    an RPC. Postgres and service_role keep EXECUTE. The helper it calls,
--    _notify_owner_email(), is already restricted the same way.

DROP FUNCTION IF EXISTS public.reorder_stops(uuid, uuid[]);

REVOKE EXECUTE ON FUNCTION public._notify_owner_new_tenant() FROM PUBLIC, anon, authenticated;
