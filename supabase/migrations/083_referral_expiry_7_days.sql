-- Migration 083: Shorten lead_referrals expiry from 14 to 7 days
--
-- A referral is time-sensitive (the underlying lead may cool off), and a
-- 14-day open window meant a non-responsive colleague could sit on it for
-- two weeks before the referrer knew to try someone else. Shortening the
-- default to 7 days nudges referrers to move on sooner. Only affects NEW
-- referrals created after this migration — existing rows keep the
-- expires_at value that was already computed for them at insert time.

ALTER TABLE lead_referrals ALTER COLUMN expires_at SET DEFAULT (now() + interval '7 days');
