# Design System Pro — Liders CRM Platform

## פקודה: `/design-system`

Design tokens מדויקים, component specs, RTL guidelines — dark theme.

---

## Color Palette

```css
:root {
  /* Backgrounds */
  --bg:        #0F172A;   /* עמוד ראשי */
  --surface:   #1E293B;   /* כרטיסים, sidebar, topbar */
  --surface2:  #273549;   /* hover states, inputs */
  --border:    #334155;   /* כל הגבולות */

  /* Brand Accent */
  --gold:      #F59E0B;
  --gold-light:#FDE68A;
  --gold-dim:  rgba(245,158,11,0.12);

  /* Text */
  --text:      #F1F5F9;   /* ראשי */
  --text-muted:#94A3B8;   /* משני */
  --text-dim:  #64748B;   /* שלישוני */

  /* Semantic — Success */
  --green:     #10B981;
  --green-bg:  rgba(16,185,129,0.12);

  /* Semantic — Error */
  --red:       #EF4444;
  --red-bg:    rgba(239,68,68,0.12);

  /* Semantic — Info */
  --blue:      #3B82F6;
  --blue-bg:   rgba(59,130,246,0.12);

  /* Semantic — Warning */
  --orange:    #F97316;
  --orange-bg: rgba(249,115,22,0.12);
}
```

---

## Typography

```css
:root {
  --font-body: 'Heebo', sans-serif;

  /* Scale */
  --text-xs:   0.75rem;   /* 12px */
  --text-sm:   0.82rem;   /* 13px */
  --text-base: 0.875rem;  /* 14px */
  --text-md:   1rem;      /* 16px */
  --text-lg:   1.1rem;    /* 17.6px */
  --text-xl:   1.5rem;    /* 24px */

  /* Weights */
  --fw-regular: 400;
  --fw-medium:  500;
  --fw-semi:    600;
  --fw-bold:    700;
  --fw-black:   800;
}
```

---

## Spacing & Layout

```css
:root {
  --space-1:  4px;
  --space-2:  8px;
  --space-3:  12px;
  --space-4:  16px;
  --space-5:  20px;
  --space-6:  24px;
  --space-8:  32px;

  --radius-sm: 8px;
  --radius:    12px;
  --radius-lg: 20px;
  --radius-full: 9999px;

  --shadow: 0 4px 24px rgba(0,0,0,0.4);
}
```

---

## Component Specs

### Stat Card
```
background: var(--surface)
border: 1px solid var(--border)
border-radius: var(--radius)
padding: 1.2rem

.stat-label: text-sm, text-muted
.stat-value: 1.8rem, bold
  .gold variant: color = --gold
  .green variant: color = --green
  .red variant: color = --red
  .blue variant: color = --blue
```

### Table
```
.table-wrap:
  background: var(--surface)
  border: 1px solid var(--border)
  border-radius: var(--radius)
  overflow: hidden

thead th:
  background: var(--surface2)
  color: text-muted
  font-size: 0.78rem

tbody td:
  border-bottom: 1px solid var(--border)
  font-size: 0.875rem

tr:hover td:
  background: var(--surface2)
```

### Badges
```css
.badge {
  display: inline-flex; align-items: center;
  padding: .2rem .6rem; border-radius: 20px;
  font-size: .75rem; font-weight: 600;
}

.badge-green  { background: var(--green-bg);  color: var(--green)  }
.badge-red    { background: var(--red-bg);    color: var(--red)    }
.badge-blue   { background: var(--blue-bg);   color: var(--blue)   }
.badge-gold   { background: var(--gold-dim);  color: var(--gold)   }
.badge-dim    { background: rgba(100,116,139,0.15); color: var(--text-dim) }
```

### Buttons
```css
/* Primary */
.btn-primary {
  background: var(--gold); color: #000;
  border: none; border-radius: var(--radius-sm);
  font-weight: 700; cursor: pointer;
}

/* Outline */
.btn-outline {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-muted);
}
.btn-outline:hover { border-color: var(--gold); color: var(--gold) }

/* Icon Button */
.btn-icon {
  width: 30px; height: 30px;
  background: var(--surface2);
  border: 1px solid var(--border);
  border-radius: 6px;
}
.btn-icon:hover { border-color: var(--gold); color: var(--gold) }
.btn-icon.danger:hover { border-color: var(--red); color: var(--red) }
```

### Modal
```
overlay: rgba(0,0,0,0.7)
.modal:
  background: var(--surface)
  border: 1px solid var(--border)
  border-radius: var(--radius-lg)
  max-width: 520px; max-height: 90vh
  padding: 1.75rem
```

---

## RTL Guidelines

```
כל component — dir="rtl" על html
text-align: right ברירת מחדל
flex-direction: row → ימין לשמאל אוטומטית ב-RTL
```
