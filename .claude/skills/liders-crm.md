# CRM Workflow Skill — Liders CRM Platform

## פקודה: `/liders-crm`

סקיל זה מספק ארכיטקטורה, entities ו-workflow לבניית features בפלטפורמת **Liders CRM**.

---

## Entities ראשיים

```typescript
interface LidersAccount {
  id: string;                 // uuid
  created_at: string;
  updated_at: string;
  business_name: string;      // שם העסק
  owner_name: string;         // שם הבעלים
  phone?: string;
  email?: string;
  business_type?: string;     // סלון יופי, קליניקה, וכו'
  plan: 'trial' | 'basic' | 'pro' | 'enterprise';
  status: 'active' | 'trial' | 'inactive' | 'churned';
  crm_url?: string;           // קישור למערכת ה-CRM של הלקוח
  supabase_project_id?: string;
  notes?: string;
  trial_ends_at?: string;
  mrr: number;                // Monthly Recurring Revenue (₪)
  next_billing_date?: string;
}

interface LidersInvoice {
  id: string;
  created_at: string;
  account_id: string;         // FK → liders_accounts
  invoice_number?: string;    // INV-YYYY-XXX
  description?: string;
  amount: number;
  currency: string;           // ILS
  status: 'pending' | 'paid' | 'overdue' | 'cancelled';
  due_date?: string;
  paid_at?: string;
  billing_month?: string;     // YYYY-MM
  notes?: string;
}
```

---

## Workflow לבניית Feature חדש

### 1. ניתוח הדרישה
```
- מה ה-entity המרכזי?
- האם נדרשת DB migration?
- האם יש RLS policies?
- האם יש automation (Make.com)?
```

### 2. Schema Supabase
```sql
-- דוגמה: הוספת טבלה חדשה
CREATE TABLE liders_new_entity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid REFERENCES liders_accounts(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  -- fields...
);

ALTER TABLE liders_new_entity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_only"
  ON liders_new_entity FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
```

### 3. צינור נתונים
```
[Admin Browser] → [index.html JS + Supabase JS] → [Supabase RLS] → [PostgreSQL]
                                                  ↓
                                           [Make.com Webhook] → [WhatsApp / Gmail]
```

### 4. Component HTML Pattern
```html
<!-- כל component — RTL, עברית, dark theme tokens -->
<div class="table-wrap">
  <table>
    <thead><tr>...</tr></thead>
    <tbody id="entity-tbody">...</tbody>
  </table>
</div>
```

---

## Checklist לפני Push

- [ ] RLS policies פועלות
- [ ] RTL/עברית תקין
- [ ] Mobile responsive (390px)
- [ ] Supabase migration נכתבה
- [ ] Dark theme tokens — לא hardcoded colors
- [ ] Auth: `auth.role() = 'authenticated'` על כל טבלה חדשה

---

## MRR Plans

| תוכנית | מחיר | תיאור |
|--------|------|-------|
| Trial | ₪0 | ניסיון חינמי 14 יום |
| Basic | ₪149/חודש | לקוח בסיסי |
| Pro | ₪299/חודש | לקוח פרו |
| Enterprise | ₪599/חודש | לקוח ארגוני |
