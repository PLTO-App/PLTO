-- PLTO: deal/project checklist for lawyer cases and interior design projects
-- Sparse jsonb keyed by a fixed template item key (defined client-side), e.g.
-- {"title_deed": {"done": true}, "caveat": {"done": false, "due_date": "2026-08-01"}}
-- Missing keys mean "not done, no due date" — nothing is written until a user
-- actually interacts with an item, so most leads keep this column null.
alter table public.leads
  add column if not exists checklist jsonb;
