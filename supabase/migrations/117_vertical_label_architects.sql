-- עדכון תווית "interior" ב-_vertical_label_he מ"מעצב פנים" ל"מעצב פנים או אדריכל",
-- כדי לשקף שאדריכלים נכללים בתחום "עיצוב פנים" הקיים (הוחלט 4/8/2026 — לא נוסף
-- vertical נפרד, רק התווית המוצגת ללקוח מתעדכנת). נקרא ב-get_client_consent_preview
-- (הודעת בקשת הסכמת לקוח) ובמנגנון הסכם ההפניה (כרגע קוד מת, ראה מיגרציה 112).

CREATE OR REPLACE FUNCTION public._vertical_label_he(p_vertical text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_vertical
    WHEN 'realestate'        THEN 'סוכן נדל"ן'
    WHEN 'realestate_lawyer' THEN 'עו"ד'
    WHEN 'interior'          THEN 'מעצב פנים או אדריכל'
    WHEN 'other'             THEN 'בעל מקצוע'
    ELSE 'בעל מקצוע'
  END;
$function$;
