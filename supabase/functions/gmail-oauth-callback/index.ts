// החיבור של תיבת הדואר המשותפת (liders.crm@gmail.com) הושבת ב-3.11.2026: הכתובת יוצאת משימוש,
// ומסך "תיבת דואר" הוסר מהתפריט. הפונקציה נשארת רק כדי שקישור ישן יקבל תשובה ברורה ולא יבצע חיבור.
// לחיבור תיבה אחרת בעתיד יש לבנות זרימה חדשה: משתמש מאומת, state חתום ושמירה לפי החשבון שאושר בפועל.
Deno.serve(() =>
  new Response(
    `<!DOCTYPE html><html dir="rtl" lang="he"><head><meta charset="utf-8"><title>PLTO</title>
<style>body{font-family:sans-serif;padding:60px;text-align:center;direction:rtl}</style></head>
<body><h1>החיבור הזה הושבת</h1><p>אין צורך בפעולה נוספת.</p></body></html>`,
    { status: 410, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
  ),
);
