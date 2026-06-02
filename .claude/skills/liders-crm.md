# CRM Workflow Skill — מלי יופי ועור

## פקודה: `/liders-crm`

סקיל זה מספק ארכיטקטורה, entities ו-workflow לבניית features במערכת ה-CRM של **מלי • יופי ועור**.

---

## Entities ראשיים

```typescript
interface Service {
  id: number;
  name: string;          // שם הטיפול
  price: number;         // מחיר בשקלים
  duration: number;      // דקות
  tag: 'פנים' | 'פרמיום' | 'רפואי' | 'רגליים' | 'הסרה';
  active: boolean;
}

interface Booking {
  id: number;
  client_name: string;
  phone: string;
  service: string;       // שם הטיפול
  service_id?: number;
  price: number;
  date: string;          // YYYY-MM-DD
  time: string;          // HH:mm
  notes: string;
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled' | 'no_show';
  created_at: string;
}

interface Client {
  id: number;
  name: string;
  phone: string;
  email?: string;
  notes?: string;
  skin_type?: string;     // סוג עור
  allergies?: string;
  last_visit?: string;
  total_visits: number;
  total_spent: number;
  tags: string[];         // VIP, חדשה, רגישת עור, etc.
}

interface Schedule {
  day: 0 | 1 | 2 | 3 | 4 | 5 | 6;  // 0=ראשון
  open: boolean;
  from: string;   // HH:mm
  to: string;     // HH:mm
  break_from?: string;
  break_to?: string;
}

interface SalonSettings {
  salon_name: string;
  tagline: string;
  pin: string;
  slot_min: number;      // ברירת מחדל גודל slot בדקות
  phone?: string;
  address?: string;
  whatsapp_number?: string;
}
```

---

## Workflow לבניית Feature חדש

### 1. ניתוח הדרישה
```
- מה הentity המרכזי?
- האם נדרשת DB migration?
- האם יש RLS policies?
- האם יש automation (Make.com / WhatsApp)?
```

### 2. Schema Supabase
```sql
-- דוגמה: הוספת טבלת לקוחות
CREATE TABLE clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text UNIQUE NOT NULL,
  email text,
  notes text DEFAULT '',
  skin_type text,
  allergies text,
  last_visit date,
  total_visits integer DEFAULT 0,
  total_spent numeric(10,2) DEFAULT 0,
  tags text[] DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
```

### 3. צינור נתונים
```
[לקוח בדפדפן] → [index.html JS] → [Supabase REST/RLS] → [PostgreSQL]
                                  ↓
                           [Make.com Webhook] → [WhatsApp / Gmail]
```

### 4. Component HTML Pattern
```html
<!-- כל component חדש — RTL, עברית, design tokens -->
<div class="admin-block">
  <div class="sec-head"><h2>כותרת</h2><div class="sec-line"></div></div>
  <!-- תוכן -->
</div>
```

---

## Checklist לפני Push

- [ ] TypeScript types מוגדרים
- [ ] RLS policies פועלות
- [ ] RTL/עברית תקין
- [ ] Mobile responsive
- [ ] Supabase migration נכתבה
- [ ] Make.com automation מוגדרת (אם נדרש)
- [ ] PIN admin מוגן

---

## שירותים קיימים (ייחוס מהיר)

| # | שם | מחיר | זמן | קטגוריה |
|---|----|------|-----|---------|
| 1 | טיפול פנים קלאסי | ₪220 | 60 דק' | פנים |
| 2 | טיפול פנים עמוק (KB Pure) | ₪320 | 75 דק' | פרמיום |
| 3 | טיפול אנטי-אייג'ינג | ₪380 | 75 דק' | רפואי |
| 4 | טיפול אקנה ובעיות עור | ₪280 | 60 דק' | רפואי |
| 5 | פדיקור רפואי | ₪200 | 60 דק' | רגליים |
| 6 | פדיקור + לק | ₪240 | 70 דק' | רגליים |
| 7 | הסרת שיער בשעווה (פנים) | ₪80 | 25 דק' | הסרה |
| 8 | עיצוב גבות | ₪70 | 20 דק' | פנים |
