// Public endpoint for an external document link (no login). Deployed with --no-verify-jwt.
// The service-role key stays on the server: it is used only to resolve the token and to sign the file URL.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { handle, makeLimiter, page } from './handler.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

// 30 openings per minute per address.
const allow = makeLimiter(30, 60 * 1000);

Deno.serve((req: Request) => {
  if (!admin) return page(500, 'משהו השתבש', 'אפשר לנסות שוב בעוד רגע.');
  return handle(req, {
    allow,
    async resolve(token) {
      const { data, error } = await admin.rpc('resolve_document_share', { p_token: token });
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : null;
      return row && typeof row.file_path === 'string' && typeof row.file_name === 'string'
        ? { file_path: row.file_path, file_name: row.file_name }
        : null;
    },
    async sign(path, fileName) {
      const { data, error } = await admin.storage
        .from('lead-documents')
        .createSignedUrl(path, 60, { download: fileName });
      return error || !data?.signedUrl ? null : data.signedUrl;
    },
  });
});
