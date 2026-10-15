// Pure validation for notify-owner. No Deno or network APIs here, so it can be
// unit-tested with plain Node (see supabase/tests/notify-owner-validate.test.ts).

export const ADMIN_EMAILS = ['info@plto.app', 'elgrablidudu@gmail.com'];
export const MAX_BODY_BYTES = 8 * 1024;

type Field = { max: number; required?: boolean };
type EventSpec = { adminOnly?: boolean; fields: Record<string, Field> };

// event name -> allowed fields. Anything else is dropped before forwarding.
export const EVENTS: Record<string, EventSpec> = {
  'support.needs_human': {
    fields: {
      ticket_id: { max: 64, required: true },
      tenant_name: { max: 120 }, agent_name: { max: 120 }, message: { max: 2000 },
    },
  },
  'support.admin_replied': {
    adminOnly: true,
    fields: {
      ticket_id: { max: 64, required: true },
      tenant_name: { max: 120 }, agent_name: { max: 120 }, agent_email: { max: 200, required: true }, response: { max: 4000 },
    },
  },
  upgrade_request: {
    fields: {
      plan: { max: 40 }, plan_name: { max: 80 }, plan_price: { max: 40 }, tenant_name: { max: 120 }, tenant_id: { max: 64 },
    },
  },
  full_service_request: {
    fields: {
      name: { max: 120, required: true }, phone: { max: 40, required: true }, need: { max: 2000 }, tenant: { max: 120 },
    },
  },
  idea_suggestion: {
    fields: {
      text: { max: 2000, required: true }, category: { max: 60 }, agent_name: { max: 120 }, tenant_name: { max: 120 },
    },
  },
};

export type Result =
  | { ok: true; payload: Record<string, string> }
  | { ok: false; status: number; error: string };

export function buildPayload(
  input: unknown,
  user: { email?: string | null },
): Result {
  if (!input || typeof input !== 'object') return { ok: false, status: 400, error: 'invalid_body' };
  const { event, data } = input as { event?: unknown; data?: unknown };
  if (typeof event !== 'string' || !Object.prototype.hasOwnProperty.call(EVENTS, event)) {
    return { ok: false, status: 400, error: 'unknown_event' };
  }
  const spec = EVENTS[event];
  const email = (user.email || '').toLowerCase();
  if (spec.adminOnly && !ADMIN_EMAILS.includes(email)) {
    return { ok: false, status: 403, error: 'forbidden' };
  }
  const src = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const payload: Record<string, string> = { event };
  for (const [name, f] of Object.entries(spec.fields)) {
    const raw = src[name];
    const v = typeof raw === 'string' ? raw.trim() : typeof raw === 'number' ? String(raw) : '';
    if (f.required && !v) return { ok: false, status: 400, error: `missing_${name}` };
    if (v) payload[name] = v.slice(0, f.max);
  }
  // Identity comes from the verified session, never from the client. The only
  // event that carries a different person's address is the admin reply, and it
  // is admin-only.
  if (!spec.adminOnly) payload.agent_email = email;
  return { ok: true, payload };
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
