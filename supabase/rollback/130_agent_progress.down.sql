-- חזרה לאחור של מיגרציה 130. מוחק את פונקציות ההתקדמות ואת הטבלה agent_progress.
-- מוחק את ההתקדמות שנשמרה בשרת (גיבוי XP בלבד). הדפדפן ממשיך לעבוד עם ההתקדמות המקומית,
-- כי הוא נופל בשקט כשהפונקציות לא קיימות. אין בטבלה שום נתון עסקי.
-- הקובץ הזה אינו בתיקיית migrations, ולכן לא יורץ אוטומטית.

DROP FUNCTION IF EXISTS public.save_my_progress(jsonb);
DROP FUNCTION IF EXISTS public.get_my_progress();
DROP TABLE IF EXISTS public.agent_progress;
