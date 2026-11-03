// The public link a client gets for a shared document is doc.html?t=<64 hex> on the PLTO site. That page
// calls this function (GET ?t=...) and gets JSON back. The function never serves HTML: on the default
// supabase.co domain the gateway rewrites HTML to text/plain with a sandbox CSP, so a page from here would
// show raw source to the client.
// Pure request handling with the database and storage calls injected, so it can be tested in plain Node
// (supabase/tests/document-share.test.ts). The token is checked by resolve_document_share() (migration 133):
// valid only if not revoked and not expired. On success the response holds a 60-second signed URL.

export const TOKEN_RE = /^[0-9a-f]{64}$/;

export const ALLOWED_ORIGINS = [
  'https://realestate.plto.app',
  'https://sales.plto.app',
  'https://plto.app',
  'https://www.plto.app',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
];

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

// Only fixed values go into the body: an error code, or the signed URL from storage.
export function json(status: number, body: { url?: string; error?: string }, origin: string | null = null): Response {
  const headers: Record<string, string> = {
    ...SECURITY_HEADERS,
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Methods': 'GET',
    'Vary': 'Origin',
  };
  return new Response(JSON.stringify(body), { status, headers });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const origin = req.headers.get('origin');
  if (req.method !== 'GET') return json(405, { error: 'method' }, origin);
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
  if (!deps.allow(ip)) return json(429, { error: 'rate_limited' }, origin);
  const token = new URL(req.url).searchParams.get('t') || '';
  if (!TOKEN_RE.test(token)) return json(404, { error: 'unavailable' }, origin);

  let file: SharedFile | null;
  try {
    file = await deps.resolve(token);
  } catch (_e) {
    return json(500, { error: 'error' }, origin);
  }
  if (!file) return json(404, { error: 'unavailable' }, origin);

  let url: string | null;
  try {
    url = await deps.sign(file.file_path, file.file_name);
  } catch (_e) {
    url = null;
  }
  if (!url) return json(500, { error: 'error' }, origin);
  return json(200, { url }, origin);
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
