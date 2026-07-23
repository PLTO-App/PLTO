-- Migration 110: bookkeeping columns for the owner-notification automation
-- (new real tenant signups, and the "20 of 30 trial days + real activity"
-- threshold that triggers handling Grow/PayMe + the Supabase Pro upgrade).
-- Both are one-shot flags stamped by the automated check so it never repeats
-- itself regardless of how often/reliably the check runs.

ALTER TABLE tenants ADD COLUMN IF NOT EXISTS owner_new_tenant_notified_at timestamptz;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS owner_trial20_notified_at    timestamptz;

-- Existing tenants (as of this migration) are already known to the owner —
-- backfill so the "new tenant" alert only fires for genuinely new signups
-- going forward, not a retroactive burst about tenants already documented
-- in CLAUDE.md.
UPDATE tenants SET owner_new_tenant_notified_at = now()
WHERE owner_new_tenant_notified_at IS NULL;
