# בדיקה מקיפה שבועית (Regression QA)

סקריפטים לבדיקת רגרסיה על `index.html`, `admin.html`, `landing.html` בלי
תלות ברשת (backend מדומה בזיכרון) + syntax check. נכתבו בסשן 17/7/2026,
ראה `CLAUDE.md` (סעיף "🧪 בדיקה מקיפה שבועית") לתהליך המלא כולל בדיקות
נוספות שלא ממוכנות כאן (Supabase advisors, בדיקה חיה מול plto.app, סקירת
קומיטים אחרונים, סריקת סגנון).

## הרצה

```bash
bash qa/run_all.sh
```

או כל קובץ בנפרד:

```bash
export NODE_PATH=/opt/node22/lib/node_modules   # playwright מותקן שם גלובלית בסביבה
node qa/qa_index.js
node qa/qa_admin.js
node qa/qa_landing.js
```

## מה זה בודק

- הדף נטען בלי שגיאות JS (page errors) או שגיאות קונסולה חריגות
- מודולי JS מרכזיים מוגדרים (הגנה מפני רגרסיית TDZ, כמו הבאג שנמצא ותוקן
  ב-11/7/2026 עם `AgentInvite`)
- `escapeHtml()` חוסם XSS בפועל
- אין גלילה אופקית ב-390px (מובייל) ו-1440px (דסקטופ, ב-landing)
- אין אזכור מיתוג ישן ("Liders"/"לידרס") גלוי בדף

## מה זה **לא** בודק (נדרש ידנית/כלי MCP)

- Supabase advisors (`mcp__Supabase__get_advisors`)
- מצב הדיפלוי החי בפועל מול plto.app (`pg_net` דרך Supabase, כי לסביבה אין
  גישת רשת ישירה)
- GitHub Actions build status
- זרימות מלאות עם DB אמיתי (הרשמה, אונבורדינג, שמירת ליד/נכס עם רענון)
