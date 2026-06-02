# Figma UI/UX Skill — מלי יופי ועור

## פקודה: `/figma-crm-ui`

עיצוב UI/UX עם Figma MCP + Canva MCP, RTL מלא, design tokens של הסלון.

---

## Design Tokens — מלי יופי ועור

```css
/* פלטת צבעים */
--ink:         #1C1410;   /* טקסט ראשי */
--espresso:    #3A2318;   /* header, buttons */
--terracotta:  #B06A4A;   /* accent, highlights */
--sand:        #D4A882;   /* secondary text, borders */
--blush:       #EDD5BF;   /* backgrounds, cards */
--parch:       #F7EFE5;   /* page background */
--ivory:       #FDFAF6;   /* white areas */
--sage:        #7A9E7E;   /* success, available */
--sage-light:  #EBF2EC;   /* success backgrounds */
--error:       #B84C4C;   /* errors, warnings */

/* Typography */
--font-display: 'Cormorant Garamond', Georgia, serif;
--font-body:    'Heebo', sans-serif;

/* Radius */
--radius-sm: 10px;
--radius-md: 16px;
--radius-lg: 24px;

/* Shadows */
--shadow-soft: 0 4px 24px rgba(28,20,16,0.08);
--shadow-card: 0 2px 12px rgba(28,20,16,0.07);
```

---

## עבודה עם Figma MCP

### שליפת design context
```
// השתמש ב: mcp__88a7dadd__get_design_context
// לקבלת tokens, components וספריות מ-Figma
```

### יצירת component חדש
```
1. get_libraries() — ראה אילו ספריות זמינות
2. get_design_context(url) — שלוף tokens קיימים
3. use_figma() — פתח עורך Figma
4. generate_diagram() — צור ERD / flow ב-FigJam
```

---

## RTL Guidelines

### כללים קריטיים
```css
/* תמיד על html */
html { direction: rtl; }

/* Flexbox — הפוך gap */
.flex-row { 
  display: flex; 
  flex-direction: row;
  /* בעברית: ימין לשמאל */
}

/* Icons ב-RTL */
.arrow-back::before { content: '→'; }   /* ← בלטינית */
.arrow-forward::before { content: '←'; }
```

### Component Patterns
```html
<!-- כרטיס שירות — RTL -->
<div class="service-card" dir="rtl">
  <div class="svc-info">
    <div class="svc-name">טיפול פנים קלאסי</div>
    <div class="svc-sub">⏱ 60 דקות</div>
    <span class="svc-tag">פנים</span>
  </div>
  <div class="svc-price-col">
    <div class="svc-price">₪220</div>
  </div>
</div>

<!-- form field — LTR לטלפון -->
<div class="form-field">
  <label>טלפון</label>
  <input type="tel" dir="ltr" placeholder="05X-XXXXXXX">
</div>
```

---

## Canva MCP — Marketing Materials

```
// mcp__3f33a9a8__generate_design — יצירת עיצוב שיווקי
// מתאים ל:
- פוסטים לרשתות חברתיות (Instagram, Facebook)
- כרטיסי ביקור דיגיטליים
- banner לאתר
- Stories עם מבצעים

// פרמטרים:
{
  brand_colors: ['#3A2318', '#B06A4A', '#D4A882'],
  font: 'Heebo',
  language: 'he',
  direction: 'rtl'
}
```

---

## Screen Inventory

| מסך | תיאור | Status |
|-----|-------|--------|
| Booking Flow | 4 שלבים: שירות → תאריך → שעה → פרטים | ✅ |
| Success Screen | אישור הזמנה | ✅ |
| About Page | פרופיל מלי | ✅ |
| Admin - Login | PIN pad | ✅ |
| Admin - Dashboard | תורים, שירותים, שעות | ✅ |
| Client Profile | כרטיס לקוח מפורט | ⏳ |
| Analytics | דוחות הכנסות, ביקורים | ⏳ |
| Notifications | WhatsApp, SMS | ⏳ |

---

## Figma File Structure (מומלץ)

```
📁 מלי יופי ועור - CRM
  📄 Design Tokens
  📄 Components Library
    🔲 Service Card
    🔲 Booking Card
    🔲 Client Card
    🔲 Slot Button
    🔲 Admin Block
  📄 Screens - Mobile
    📱 Booking Flow
    📱 Admin Panel
  📄 Screens - Desktop
  📄 Marketing Assets
```
