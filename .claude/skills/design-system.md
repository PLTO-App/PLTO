# Design System Pro — מלי יופי ועור

## פקודה: `/design-system`

Design tokens מדויקים, component specs, RTL guidelines.

---

## Color Palette

```css
:root {
  /* Primary — Espresso & Terracotta */
  --color-ink:         #1C1410;
  --color-espresso:    #3A2318;
  --color-espresso-60: rgba(58,35,24,0.6);
  --color-espresso-20: rgba(58,35,24,0.2);
  --color-terracotta:  #B06A4A;
  --color-terracotta-light: rgba(176,106,74,0.15);

  /* Neutrals — Sand & Blush */
  --color-sand:        #D4A882;
  --color-blush:       #EDD5BF;
  --color-parch:       #F7EFE5;
  --color-ivory:       #FDFAF6;

  /* Semantic */
  --color-success:     #7A9E7E;
  --color-success-bg:  #EBF2EC;
  --color-error:       #B84C4C;
  --color-error-bg:    rgba(184,76,76,0.1);
  --color-warning:     #C8A028;
  --color-warning-bg:  rgba(200,160,40,0.1);

  /* Text */
  --text-primary:   var(--color-ink);
  --text-secondary: #9A7E6F;
  --text-muted:     #B89A8A;
  --text-on-dark:   var(--color-ivory);
}
```

---

## Typography Scale

```css
:root {
  --font-display: 'Cormorant Garamond', Georgia, serif;
  --font-body:    'Heebo', sans-serif;

  /* Scale */
  --text-xs:   0.72rem;   /* 11.5px */
  --text-sm:   0.8rem;    /* 12.8px */
  --text-base: 0.9rem;    /* 14.4px */
  --text-md:   1rem;      /* 16px */
  --text-lg:   1.2rem;    /* 19.2px */
  --text-xl:   1.5rem;    /* 24px */
  --text-2xl:  2rem;      /* 32px */
  --text-hero: 2.2rem;    /* 35.2px */

  /* Weights */
  --fw-light:   300;
  --fw-regular: 400;
  --fw-medium:  500;
  --fw-semi:    600;
  --fw-bold:    700;
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
  --space-10: 40px;

  /* Radius */
  --radius-sm: 10px;
  --radius-md: 16px;
  --radius-lg: 24px;
  --radius-xl: 32px;
  --radius-full: 9999px;

  /* Shadows */
  --shadow-xs:   0 1px 4px rgba(28,20,16,0.06);
  --shadow-sm:   0 2px 12px rgba(28,20,16,0.07);
  --shadow-md:   0 4px 24px rgba(28,20,16,0.08);
  --shadow-lg:   0 8px 48px rgba(28,20,16,0.12);
}
```

---

## Component Specs

### Service Card
```
┌─────────────────────────────────────┐
│  [tag pill]                         │
│  שם הטיפול (font-body, fw-700)      │
│  ⏱ XX דקות (text-secondary, text-sm)│
│                        ₪XXX         │
│                     (terracotta)     │
└─────────────────────────────────────┘
border: 1.5px solid blush
border-radius: radius-md
padding: 16px
selected: border-color: terracotta, bg: terracotta-light
```

### Slot Button
```
Normal:    bg=white, border=blush, text=ink
Selected:  bg=terracotta, border=terracotta, text=ivory
Booked:    bg=parch, border=blush, text=muted, cursor=default
Width:     calc(25% - 6px) — 4 columns
Height:    40px
Radius:    radius-sm
```

### Admin Block
```
background: white
border-radius: radius-lg
padding: 24px
box-shadow: shadow-sm
margin-bottom: 24px

Header:
  font-size: text-lg
  font-weight: fw-semi
  color: espresso
```

### Buttons
```css
/* Primary */
.btn-main {
  background: var(--espresso);
  color: var(--ivory);
  border-radius: var(--radius-full);
  padding: 14px 28px;
  font-family: var(--font-body);
  font-size: var(--text-base);
  font-weight: var(--fw-medium);
  letter-spacing: 0.04em;
}

/* Ghost */
.btn-ghost {
  background: transparent;
  border: 1.5px solid rgba(58,35,24,0.25);
  color: var(--espresso);
  border-radius: var(--radius-full);
  padding: 12px 24px;
}
```

---

## Tag Pills — Service Categories

```css
.svc-tag {
  background: var(--parch);
  border: 1px solid var(--blush);
  border-radius: var(--radius-full);
  color: var(--terracotta);
  font-size: var(--text-xs);
  padding: 3px 10px;
}
```

---

## Iconography

| Symbol | שימוש |
|--------|-------|
| 🌿 | logo, brand identity |
| 📅 | תאריכים, הזמנות |
| ⏱ | משך טיפול |
| ✓ | הצלחה, confirmation |
| 🔒 | admin lock |
| 💾 | שמירה |
| ✦ | badge, premium |

---

## Dark Mode Support (Future)

```css
@media (prefers-color-scheme: dark) {
  :root {
    --color-ink:    #F7EFE5;
    --color-ivory:  #1C1410;
    --color-parch:  #2A1E16;
    /* blush/sand נשארים — warm neutrals עובדים */
  }
}
```
