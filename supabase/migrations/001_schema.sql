-- ══════════════════════════════════════════════════
--  Liders CRM — Schema Migration
--  Project: scyfywvzoogfrlalgftv (eu-central-1)
--  Run this to recreate the full DB from scratch
-- ══════════════════════════════════════════════════

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Tables ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS admin_auth (
  id       integer NOT NULL DEFAULT 1,
  pin_hash text    NOT NULL,
  CONSTRAINT admin_auth_pkey PRIMARY KEY (id),
  CONSTRAINT admin_auth_single_row CHECK (id = 1)
);

CREATE TABLE IF NOT EXISTS crm_settings (
  id           integer NOT NULL DEFAULT 1,
  company_name text    NOT NULL DEFAULT 'Liders CRM',
  tagline      text    NOT NULL DEFAULT 'הפלטפורמה שהופכת לידים לעסקאות',
  CONSTRAINT crm_settings_pkey PRIMARY KEY (id),
  CONSTRAINT crm_settings_single_row CHECK (id = 1)
);

CREATE TABLE IF NOT EXISTS leads (
  id          bigint                   NOT NULL DEFAULT nextval('leads_id_seq'),
  name        text                     NOT NULL,
  company     text,
  phone       text,
  email       text,
  deal_value  integer                  NOT NULL DEFAULT 0,
  stage_id    smallint                 NOT NULL DEFAULT 1,
  notes       text                     NOT NULL DEFAULT '',
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  updated_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT leads_pkey PRIMARY KEY (id),
  CONSTRAINT leads_stage_id_check CHECK (stage_id BETWEEN 1 AND 5)
);

CREATE SEQUENCE IF NOT EXISTS leads_id_seq OWNED BY leads.id;

-- ── RLS ───────────────────────────────────────────

ALTER TABLE admin_auth   ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads        ENABLE ROW LEVEL SECURITY;

-- crm_settings: anon can only read
CREATE POLICY anon_read_crm_settings ON crm_settings
  FOR SELECT TO anon USING (true);

-- leads: anon full CRUD (gated by frontend PIN)
CREATE POLICY anon_all_leads ON leads
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- admin_auth: no public policies — access only via SECURITY DEFINER RPCs

-- ── Functions ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.verify_admin_pin(pin_input text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_hash TEXT;
BEGIN
  SELECT pin_hash INTO stored_hash FROM public.admin_auth WHERE id = 1;
  IF stored_hash IS NULL THEN RETURN FALSE; END IF;
  RETURN stored_hash = crypt(pin_input, stored_hash);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_crm_settings(
  pin_input    text,
  p_company_name text,
  p_tagline    text,
  p_new_pin    text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.verify_admin_pin(pin_input) THEN RETURN FALSE; END IF;
  UPDATE public.crm_settings
    SET company_name = p_company_name,
        tagline      = p_tagline
    WHERE id = 1;
  IF p_new_pin IS NOT NULL AND p_new_pin ~ '^\d{4}$' THEN
    UPDATE public.admin_auth
      SET pin_hash = crypt(p_new_pin, gen_salt('bf'))
      WHERE id = 1;
  END IF;
  RETURN TRUE;
END;
$$;
