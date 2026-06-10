-- ══════════════════════════════════════════════════
--  Liders CRM — Seed Data
--  Last exported: 2026-06-10
--  Run AFTER 001_schema.sql
-- ══════════════════════════════════════════════════

-- ── crm_settings ──────────────────────────────────
INSERT INTO crm_settings (id, company_name, tagline)
VALUES (1, 'Liders CRM', 'הפלטפורמה שהופכת לידים לעסקאות')
ON CONFLICT (id) DO UPDATE
  SET company_name = EXCLUDED.company_name,
      tagline      = EXCLUDED.tagline;

-- ── leads ─────────────────────────────────────────
INSERT INTO leads (id, name, company, phone, email, deal_value, stage_id, notes, created_at, updated_at) VALUES
(1, 'דוד כהן',    'Tech Solutions',    '052-1111111', 'david@tech.co.il',    15000, 2, 'פגישה ב-15 ביוני',                          '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(2, 'רוני לוי',   'StartupX',          '054-2222222', 'roni@startupx.io',    45000, 3, 'הצעה נשלחה אתמול',                          '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(3, 'מיכאל גל',   'BigCorp',           '050-3333333', 'michael@bigcorp.co.il',80000, 4, 'שלב מו"מ סופי',                            '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(4, 'שרה אברהם',  'SME Pro',           '053-4444444', 'sara@sme.co.il',      25000, 1, 'ליד חדש מפייסבוק',                          '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(5, 'יוסי מלכה',  'Digital Agency',    '055-5555555', 'yosi@digital.co.il',  60000, 5, 'עסקה נסגרה!',                               '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(6, 'נועה שפיר',  'Retail Chain',      '058-6666666', 'noa@retail.co.il',    35000, 2, 'בשיחת פולו-אפ',                             '2026-06-10 07:18:57+00', '2026-06-10 07:18:57+00'),
(7, 'אבי לוי',    'רכבי יוקרה במוו',   '05897777777', NULL,                    350, 3, 'מבקש שיחזרו אליו שבוע הבא יום רביעי בשעה 12:30. מבקש הנחה, הצגתי אופציה של ברטר', '2026-06-10 13:18:41+00', '2026-06-10 13:18:40+00')
ON CONFLICT (id) DO NOTHING;

-- Sync sequence after manual inserts
SELECT setval('leads_id_seq', (SELECT MAX(id) FROM leads));

-- ── admin_auth ────────────────────────────────────
-- PIN hash is NOT stored here for security.
-- To set the PIN, run:
--   INSERT INTO admin_auth (id, pin_hash)
--   VALUES (1, crypt('YOUR_4_DIGIT_PIN', gen_salt('bf')))
--   ON CONFLICT (id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash;
