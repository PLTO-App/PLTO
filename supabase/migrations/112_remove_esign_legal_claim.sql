-- Migration 112: remove premature legal-validity claim from the digital
-- signature roadmap item.
--
-- roadmap_items (047) seeded "חתימה דיגיטלית לחוזים" with a description that
-- promised "חתימה אלקטרונית חוקית" (legally valid e-signature). The feature
-- is not built at all yet, and CLAUDE.md's own standing rule for this exact
-- feature forbids presenting it as legally binding before a certified
-- e-signature provider + legal review are in place. Reword to describe the
-- planned capability without asserting legal validity.

UPDATE roadmap_items
SET description = 'שליחת חוזה ללקוח לחתימה אלקטרונית מרחוק ישירות מהטלפון',
    updated_at = now()
WHERE title = 'חתימה דיגיטלית לחוזים';
