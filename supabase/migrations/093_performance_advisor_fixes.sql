-- 093_performance_advisor_fixes.sql
-- Fixes flagged by Supabase Performance Advisor (get_advisors, 14/7/2026):
-- 1) Missing covering indexes on foreign keys (17 FKs)
-- 2) RLS policies re-evaluating auth.<fn>() per row instead of once (initplan)
-- 3) Duplicate permissive SELECT policies on shared_leads merged into one
-- No data volume impact today (tables are near-empty pre-launch), but cheap to
-- fix now before real customer data/traffic makes it expensive to fix live.

-- 1) Covering indexes for unindexed foreign keys
CREATE INDEX IF NOT EXISTS idx_agent_invites_invited_by ON public.agent_invites(invited_by);
CREATE INDEX IF NOT EXISTS idx_agent_invites_tenant_id ON public.agent_invites(tenant_id);
CREATE INDEX IF NOT EXISTS idx_client_consents_lead_id ON public.client_consents(lead_id);
CREATE INDEX IF NOT EXISTS idx_community_jokes_tenant_id ON public.community_jokes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_lead_documents_agent_id ON public.lead_documents(agent_id);
CREATE INDEX IF NOT EXISTS idx_lead_documents_lead_id ON public.lead_documents(lead_id);
CREATE INDEX IF NOT EXISTS idx_lead_documents_tenant_id ON public.lead_documents(tenant_id);
CREATE INDEX IF NOT EXISTS idx_lead_referrals_accepted_by_tenant_id ON public.lead_referrals(accepted_by_tenant_id);
CREATE INDEX IF NOT EXISTS idx_lead_referrals_lead_id ON public.lead_referrals(lead_id);
CREATE INDEX IF NOT EXISTS idx_lead_referrals_opportunity_id ON public.lead_referrals(opportunity_id);
CREATE INDEX IF NOT EXISTS idx_lead_referrals_to_tenant_id ON public.lead_referrals(to_tenant_id);
CREATE INDEX IF NOT EXISTS idx_partner_opportunities_selected_application_id ON public.partner_opportunities(selected_application_id);
CREATE INDEX IF NOT EXISTS idx_referral_agreements_to_tenant_id ON public.referral_agreements(to_tenant_id);
CREATE INDEX IF NOT EXISTS idx_roadmap_item_votes_agent_id ON public.roadmap_item_votes(agent_id);
CREATE INDEX IF NOT EXISTS idx_shared_lead_messages_sender_tenant_id ON public.shared_lead_messages(sender_tenant_id);
CREATE INDEX IF NOT EXISTS idx_shared_leads_lead_id ON public.shared_leads(lead_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_tenant_id ON public.support_tickets(tenant_id);

-- 2) RLS initplan fixes: wrap auth.<fn>() so it evaluates once per query
DROP POLICY IF EXISTS "ai_usage_own_read" ON public.ai_usage;
CREATE POLICY "ai_usage_own_read" ON public.ai_usage
  FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "tenant_isolation_docs" ON public.lead_documents;
CREATE POLICY "tenant_isolation_docs" ON public.lead_documents
  FOR ALL TO public
  USING (tenant_id = (SELECT agent_users.tenant_id FROM agent_users WHERE agent_users.auth_user_id = (select auth.uid()) LIMIT 1))
  WITH CHECK (tenant_id = (SELECT agent_users.tenant_id FROM agent_users WHERE agent_users.auth_user_id = (select auth.uid()) LIMIT 1));

DROP POLICY IF EXISTS "authenticated insert own joke" ON public.community_jokes;
CREATE POLICY "authenticated insert own joke" ON public.community_jokes
  FOR INSERT TO authenticated
  WITH CHECK (submitted_by = (select auth.uid()));

DROP POLICY IF EXISTS "authenticated read own jokes" ON public.community_jokes;
CREATE POLICY "authenticated read own jokes" ON public.community_jokes
  FOR SELECT TO authenticated
  USING (submitted_by = (select auth.uid()));

-- 3) Merge shared_leads' two permissive SELECT policies into one
DROP POLICY IF EXISTS "shared_leads_owner_read" ON public.shared_leads;
DROP POLICY IF EXISTS "shared_leads_partner_read" ON public.shared_leads;
CREATE POLICY "shared_leads_read" ON public.shared_leads
  FOR SELECT TO authenticated
  USING (
    owner_tenant_id = get_my_tenant_id()
    OR (partner_tenant_id = get_my_tenant_id() AND status = 'active')
  );
