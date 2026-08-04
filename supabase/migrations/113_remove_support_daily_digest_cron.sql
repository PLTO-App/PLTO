-- Migration 113: remove the daily support-digest cron entirely
--
-- The daily digest (`plto-support-daily-digest`, migrations 057/058/075) emailed
-- "דוח תמיכה יומי" every single day at 17:30 UTC, even with 0 tickets — pure noise.
-- Real-time escalation already exists and works today: `SupportChat.send()` in
-- index.html fires the `support.needs_human` webhook the moment a ticket actually
-- needs a human (AI couldn't resolve it / quota exhausted / error), and the Make
-- scenario "PLTO — Lead Notifications" already has a live route for that event
-- ("תמיכה - צריך התערבות אנושית" → 🆘 email to info@plto.app). So the daily digest
-- was fully redundant with an always-on real-time notification, not a replacement
-- for one. Simplest fix: drop the cron job. The now-dead "support.daily_digest"
-- Make route is left in place (harmless, no longer triggered by anything).

SELECT cron.unschedule('plto-support-daily-digest');
