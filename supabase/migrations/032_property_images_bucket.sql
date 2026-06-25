-- Create property-images storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'property-images',
  'property-images',
  true,
  10485760,
  ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/heic']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/heic'];

-- Allow authenticated users to upload/update in their own tenant folder
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='property-images tenant upload'
  ) THEN
    CREATE POLICY "property-images tenant upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'property-images');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='property-images tenant update'
  ) THEN
    CREATE POLICY "property-images tenant update" ON storage.objects
      FOR UPDATE TO authenticated
      USING (bucket_id = 'property-images');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='property-images public read'
  ) THEN
    CREATE POLICY "property-images public read" ON storage.objects
      FOR SELECT TO public
      USING (bucket_id = 'property-images');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='property-images tenant delete'
  ) THEN
    CREATE POLICY "property-images tenant delete" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'property-images');
  END IF;
END $$;
