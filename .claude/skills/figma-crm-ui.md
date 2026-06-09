# Figma UI/UX Skill — Liders CRM Platform

## פקודה: `/figma-crm-ui`

עיצוב UI/UX עם Figma MCP + Canva MCP, RTL מלא, dark theme tokens של Liders CRM.

---

## Design Tokens — Liders CRM

```css
:root {
  /* Background */
  --bg:        #0F172A;   /* עמוד ראשי */
  --surface:   #1E293B;   /* כרטיסים, topbar */
  --surface2:  #273549;   /* hover, inputs */
  --border:    #334155;   /* גבולות */

  /* Brand */
  --gold:      #F59E0B;   /* accent ראשי */
  --gold-light:#FDE68A;
  --gold-dim:  rgba(245,158,11,0.12);

  /* Text */
  --text:      #F1F5F9;
  --text-muted:#94A3B8;
  --text-dim:  #64748B;

  /* Semantic */
  --green:     #10B981;
  --green-bg:  rgba(16,185,129,0.12);
  --red:       #EF4444;
  --red-bg:    rgba(239,68,68,0.12);
  --blue:      #3B82F6;
  --blue-bg:   rgba(59,130,246,0.12);
  --orange:    #F97316;

  /* Radius */
  --radius-sm: 8px;
  --radius:    12px;
  --radius-lg: 20px;

  /* Shadows */
  --shadow: 0 4px 24px rgba(0,0,0,0.4);
}
```

---

## עבודה עם Figma MCP

### שליפת design context
```
// mcp__88a7dadd__get_design_context
// לקבלת tokens, components וספריות מ-Figma
```

### יצירת component חדש
```
1. get_libraries() — ראה ספריות זמינות
2. get_design_context(url) — שלוף tokens קיימים
3. use_figma() — פתח עורך Figma
4. generate_diagram() — צור ERD / flow ב-FigJam
```

---

## RTL Guidelines

### כללים קריטיים
```css
html { direction: rtl; }

/* Icons ב-RTL */
.arrow-back::before    { content: '→'; }
.arrow-forward::before { content: '←'; }
```

### Component Patterns
```html
<!-- Badge -->
<span class="badge badge-green">פעיל</span>
<span class="badge badge-blue">ניסיון</span>
<span class="badge badge-gold">Pro</span>
<span class="badge badge-red">חריגה</span>

<!-- Table Row -->
<tr>
  <td><strong>שם עסק</strong></td>
  <td><span class="badge badge-gold">Pro</span></td>
  <td style="color:var(--gold)">₪299</td>
</tr>

<!-- Input field -->
<div class="form-group">
  <label>שם העסק *</label>
  <input type="text" id="acc-business-name">
</div>
```

---

## Canva MCP — Marketing Materials

```
// mcp__3f33a9a8__generate_design
// מתאים ל:
- פוסטים לרשתות חברתיות
- pitch deck ללקוחות פוטנציאליים
- onboarding materials

// פרמטרים:
{
  brand_colors: ['#0F172A', '#F59E0B', '#1E293B'],
  font: 'Heebo',
  language: 'he',
  direction: 'rtl'
}
```

---

## Screen Inventory — Admin Dashboard

| מסך | תיאור | Status |
|-----|-------|--------|
| Auth — Login | Email + Password | ✅ |
| Dashboard | Stats + recent accounts | ✅ |
| Accounts | רשימה + חיפוש + פילטר | ✅ |
| Account Modal | הוסף/ערוך לקוח | ✅ |
| Invoices | חשבוניות + סיכומים | ✅ |
| Invoice Modal | הוסף חשבונית | ✅ |
| Client CRM | external link | ✅ |

---

## Figma File Structure (מומלץ)

```
📁 Liders CRM — Admin Dashboard
  📄 Design Tokens (dark theme)
  📄 Components Library
    🔲 Stat Card
    🔲 Table Row
    🔲 Badge
    🔲 Button (primary/outline/icon)
    🔲 Modal
    🔲 Toast
  📄 Screens — Desktop
    🖥️ Auth
    🖥️ Dashboard
    🖥️ Accounts
    🖥️ Invoices
  📄 Screens — Mobile (390px)
```
