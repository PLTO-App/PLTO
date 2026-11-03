// The public link a client gets for a shared document: GET ?t=<64 hex>. Pure request handling with the
// database and storage calls injected, so it can be tested in plain Node (supabase/tests/document-share.test.ts).
// The token is checked by resolve_document_share() (migration 133): valid only if not revoked and not expired.
// On success the client is redirected to a 60-second signed URL of the private file.

export const TOKEN_RE = /^[0-9a-f]{64}$/;

export type SharedFile = { file_path: string; file_name: string };
export type Deps = {
  resolve(token: string): Promise<SharedFile | null>;
  sign(path: string, fileName: string): Promise<string | null>;
  allow(key: string): boolean;
};

const SECURITY_HEADERS: Record<string, string> = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex, nofollow',
  'X-Content-Type-Options': 'nosniff',
};

// Static text only: nothing from the request or the database is written into the page.
export function page(status: number, title: string, text: string): Response {
  const body = `<!DOCTYPE html><html dir="rtl" lang="he"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>PLTO</title>
<style>body{font-family:system-ui,sans-serif;margin:0;padding:48px 20px;text-align:center;direction:rtl;color:#0F1F3D;background:#F1F5F9}
h1{font-size:22px;margin:0 0 12px}p{font-size:16px;color:#475569;line-height:1.6;margin:0}</style></head>
<body><h1>${title}</h1><p>${text}</p></body></html>`;
  return new Response(body, {
    status,
    headers: {
      ...SECURITY_HEADERS,
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'",
    },
  });
}

const unavailable = () =>
  page(404, 'הקישור לא זמין', 'ייתכן שתוקף הקישור פג או שהוא בוטל. אפשר לבקש קישור חדש ממי ששלח אותו.');

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return page(405, 'הפעולה לא נתמכת', 'אפשר רק לפתוח את הקישור.');
  }
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
  if (!deps.allow(ip)) {
    return page(429, 'יותר מדי ניסיונות', 'אפשר לנסות שוב בעוד כמה דקות.');
  }
  const token = new URL(req.url).searchParams.get('t') || '';
  if (!TOKEN_RE.test(token)) return unavailable();

  let file: SharedFile | null;
  try {
    file = await deps.resolve(token);
  } catch (_e) {
    return page(500, 'משהו השתבש', 'אפשר לנסות שוב בעוד רגע.');
  }
  if (!file) return unavailable();

  let url: string | null;
  try {
    url = await deps.sign(file.file_path, file.file_name);
  } catch (_e) {
    url = null;
  }
  if (!url) return page(500, 'משהו השתבש', 'אפשר לנסות שוב בעוד רגע.');
  return new Response(null, { status: 302, headers: { ...SECURITY_HEADERS, Location: url } });
}

// Best-effort per-instance limiter (the Edge runtime may run several instances).
export function makeLimiter(limit: number, windowMs: number, now: () => number = Date.now) {
  const hits = new Map<string, number[]>();
  return (key: string): boolean => {
    const t = now();
    const arr = (hits.get(key) || []).filter((x) => t - x < windowMs);
    if (arr.length >= limit) { hits.set(key, arr); return false; }
    arr.push(t); hits.set(key, arr);
    return true;
  };
}
