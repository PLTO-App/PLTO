# Supabase Security — Liders CRM Platform

## פקודה: `/supabase-security`

RLS policies, auth, secrets, audit לכל טבלאות פלטפורמת Liders CRM.

---

## RLS Policies — טבלאות Admin

### liders_accounts
```sql
ALTER TABLE liders_accounts ENABLE ROW LEVEL SECURITY;

-- גישה למשתמש מאומת בלבד
CREATE POLICY "liders_accounts_auth_only"
  ON liders_accounts
  FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
```

### liders_invoices
```sql
ALTER TABLE liders_invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "liders_invoices_auth_only"
  ON liders_invoices
  FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
```

---

## Auth Setup

### Admin Authentication (Supabase Auth)
```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);

async function adminLogin(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  return { data, error };
}

async function adminLogout() {
  return await supabase.auth.signOut();
}

// בדיקת session פעיל
async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}
```

---

## Secrets Management

### .env.local (לעולם לא commit!)
```bash
SUPABASE_URL=https://scyfywvzoogfrlalgftv.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...  # server-side only
ANTHROPIC_API_KEY=sk-ant-...
MAKE_WEBHOOK_URL=https://hook.eu1.make.com/...
```

### .gitignore חובה
```
.env.local
.env.production
*.key
```

---

## Security Checklist

```
אימות:
□ Supabase Auth email/password (לא PIN)
□ Session timeout אוטומטי
□ onAuthStateChange מטפל ב-logout

נתונים:
□ RLS פועל על liders_accounts
□ RLS פועל על liders_invoices
□ אין service_role_key בצד הלקוח
□ Email/phone לא מוצגים בלוגים

API:
□ CORS מוגבל ל-domain הרלוונטי
□ Input validation על כל שדות

Supabase:
□ Advisors scan (get_advisors) — נקי
□ Extensions מינימליות
□ Webhook secret validation
```

---

## Audit Trail

```sql
CREATE TABLE liders_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  action text NOT NULL,   -- INSERT, UPDATE, DELETE
  record_id uuid,
  old_data jsonb,
  new_data jsonb,
  performed_by text,      -- email של האדמין
  created_at timestamptz DEFAULT now()
);

ALTER TABLE liders_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_auth_only"
  ON liders_audit_log FOR ALL
  USING (auth.role() = 'authenticated');

-- Trigger אוטומטי
CREATE OR REPLACE FUNCTION liders_audit_trigger()
RETURNS trigger AS $$
BEGIN
  INSERT INTO liders_audit_log(table_name, action, record_id, old_data, new_data)
  VALUES (TG_TABLE_NAME, TG_OP, COALESCE(NEW.id, OLD.id),
          row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER accounts_audit
  AFTER INSERT OR UPDATE OR DELETE ON liders_accounts
  FOR EACH ROW EXECUTE FUNCTION liders_audit_trigger();

CREATE TRIGGER invoices_audit
  AFTER INSERT OR UPDATE OR DELETE ON liders_invoices
  FOR EACH ROW EXECUTE FUNCTION liders_audit_trigger();
```
