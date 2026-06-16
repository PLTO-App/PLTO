-- Add 'demo' as allowed source value for demo/testing leads
ALTER TABLE leads
  DROP CONSTRAINT IF EXISTS leads_source_check;

ALTER TABLE leads
  ADD CONSTRAINT leads_source_check
  CHECK (source IN ('yad2','madlan','facebook','instagram','referral',
                    'website','call','whatsapp','email','ad','other','demo'));
