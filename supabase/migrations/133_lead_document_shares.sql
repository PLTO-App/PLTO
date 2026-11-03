-- 133: מסמכי לקוחות בלי קישורים ציבוריים קבועים.
--
-- המיגרציה מעבירה את מסמכי הלקוחות לאחסון פרטי עם שיתוף מבוקר:
--   1. הבאקט פרטי. במסד נשמר רק נתיב הקובץ (file_path), בתוך תיקיית העסק והליד.
--   2. גישה פנימית: משתמש מחובר באותו עסק פותח קובץ בקישור חתום קצר (מדיניות storage הקיימת
--      lead_docs_read מגבילה לתיקיית העסק).
--   3. שיתוף חיצוני ללקוח: קישור עם טוקן אקראי, בתוקף 7 ימים, שאפשר לבטל. במסד נשמר רק hash של
--      הטוקן. פונקציית Edge document-share מאמתת אותו דרך resolve_document_share (service_role בלבד)
--      ומפנה לקישור חתום של 60 שניות.
--   4. ביטול קישור לא מוחק את המסמך. מחיקת מסמך מוחקת את הקבצים בצד הלקוח דרך Storage API
--      (מדיניות lead_docs_delete), ואת קישורי השיתוף שלו (ON DELETE CASCADE).
--
-- אין כרגע מסמכים בבאקט ובטבלה (נבדק ב-3.11.2026), ולכן אין צורך בהמרת נתונים קיימים. בכל זאת
-- המיגרציה ממירה קישור ציבורי ישן לנתיב, ונכשלת אם נשאר מסמך בלי נתיב תקין.

-- 1. lead_documents: נתיב הקובץ במקום קישור ציבורי
ALTER TABLE public.lead_documents ADD COLUMN IF NOT EXISTS file_path text;

UPDATE public.lead_documents
   SET file_path = substring(file_url FROM '/storage/v1/object/public/lead-documents/(.+)$')
 WHERE file_path IS NULL AND file_url IS NOT NULL;

DO $mig$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lead_documents WHERE file_path IS NULL) THEN
    RAISE EXCEPTION '133: a lead document has no storage path';
  END IF;
END
$mig$;

ALTER TABLE public.lead_documents ALTER COLUMN file_path SET NOT NULL;
ALTER TABLE public.lead_documents ALTER COLUMN file_url DROP NOT NULL;
UPDATE public.lead_documents SET file_url = NULL WHERE file_url IS NOT NULL;

ALTER TABLE public.lead_documents DROP CONSTRAINT IF EXISTS lead_documents_no_public_url;
ALTER TABLE public.lead_documents ADD CONSTRAINT lead_documents_no_public_url CHECK (file_url IS NULL);

-- הנתיב חייב להיות בתיקיית העסק והליד של המסמך. זה חשוב כי שיתוף חיצוני חותם את הנתיב עם מפתח שירות:
-- בלי הבדיקה הזו אפשר היה ליצור שורה שמצביעה לקובץ של עסק אחר ולשתף אותו.
ALTER TABLE public.lead_documents DROP CONSTRAINT IF EXISTS lead_documents_path_in_folder;
ALTER TABLE public.lead_documents ADD CONSTRAINT lead_documents_path_in_folder CHECK (
  split_part(file_path, '/', 1) = tenant_id::text
  AND split_part(file_path, '/', 2) = lead_id::text
  AND split_part(file_path, '/', 3) <> ''
  AND file_path !~ '(^|/)\.\.(/|$)'
);

-- 2. קישורי שיתוף חיצוניים
CREATE TABLE IF NOT EXISTS public.lead_document_shares (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id      uuid NOT NULL REFERENCES public.lead_documents(id) ON DELETE CASCADE,
  tenant_id        uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  token_hash       text NOT NULL UNIQUE,
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  revoked_at       timestamptz,
  last_accessed_at timestamptz,
  access_count     integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS lead_document_shares_document_idx ON public.lead_document_shares (document_id);
CREATE INDEX IF NOT EXISTS lead_document_shares_tenant_created_idx ON public.lead_document_shares (tenant_id, created_at);

ALTER TABLE public.lead_document_shares ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lead_document_shares_tenant_read ON public.lead_document_shares;
CREATE POLICY lead_document_shares_tenant_read ON public.lead_document_shares
  FOR SELECT TO authenticated USING (tenant_id = public.get_my_tenant_id());

-- קריאה בלבד, ובלי token_hash. יצירה וביטול רק דרך הפונקציות למטה.
REVOKE ALL ON TABLE public.lead_document_shares FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, document_id, created_at, expires_at, revoked_at, last_accessed_at, access_count)
  ON public.lead_document_shares TO authenticated;

-- 3. פונקציות
CREATE OR REPLACE FUNCTION public.create_document_share(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_tenant  uuid;
  v_doc     uuid;
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := now() + interval '7 days';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant := public.get_my_tenant_id();
  SELECT d.tenant_id INTO v_doc FROM public.lead_documents d WHERE d.id = p_document_id;
  IF v_tenant IS NULL OR v_doc IS NULL OR v_doc <> v_tenant THEN
    RAISE EXCEPTION 'document_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF (SELECT count(*) FROM public.lead_document_shares s
       WHERE s.tenant_id = v_tenant AND s.created_at > now() - interval '1 day') >= 100 THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'P0001';
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO public.lead_document_shares (document_id, tenant_id, token_hash, created_by, expires_at)
  VALUES (p_document_id, v_tenant, encode(extensions.digest(v_token, 'sha256'), 'hex'), v_uid, v_expires)
  RETURNING id INTO v_id;

  -- הטוקן חוזר פעם אחת בלבד. במסד נשמר רק ה-hash שלו.
  RETURN jsonb_build_object('id', v_id, 'token', v_token, 'expires_at', v_expires);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_document_share(p_share_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant := public.get_my_tenant_id();
  IF v_tenant IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.lead_document_shares s WHERE s.id = p_share_id AND s.tenant_id = v_tenant
  ) THEN
    RAISE EXCEPTION 'share_not_found' USING ERRCODE = 'P0002';
  END IF;
  UPDATE public.lead_document_shares
     SET revoked_at = now()
   WHERE id = p_share_id AND tenant_id = v_tenant AND revoked_at IS NULL;
  RETURN true;
END;
$$;

-- לשימוש פונקציית Edge בלבד (מפתח שירות). אותה תשובה ריקה לטוקן שגוי, שפג או שבוטל.
CREATE OR REPLACE FUNCTION public.resolve_document_share(p_token text)
RETURNS TABLE (file_path text, file_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_doc uuid;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RETURN;
  END IF;
  UPDATE public.lead_document_shares s
     SET last_accessed_at = now(), access_count = s.access_count + 1
   WHERE s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     AND s.revoked_at IS NULL
     AND s.expires_at > now()
  RETURNING s.document_id INTO v_doc;
  IF v_doc IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT d.file_path, d.file_name FROM public.lead_documents d WHERE d.id = v_doc;
END;
$$;

REVOKE ALL ON FUNCTION public.create_document_share(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_document_share(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_document_share(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_document_share(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_document_share(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_document_share(text) TO service_role;

-- 4. הבאקט פרטי: אין יותר קישורים ציבוריים קבועים
UPDATE storage.buckets SET public = false WHERE id = 'lead-documents';
