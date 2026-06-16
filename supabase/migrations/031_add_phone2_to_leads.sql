-- Add optional second phone number to leads (for couples / multiple contacts)
ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS phone2 text;
