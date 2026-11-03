// מזהי המשתמשים (auth.users.id) של בעלי PLTO. זו אותה רשימה כמו ב-_is_plto_admin() במיגרציה 130,
// ושינוי באחת מחייב שינוי גם בשנייה. הזיהוי לפי uid ולא לפי אימייל, כי כתובת אפשר לרשום מחדש ו-uid לא.
// קוד טהור בלי Deno ובלי רשת, כך שאפשר לבדוק אותו ב-Node.
export const PLTO_ADMIN_USER_IDS: readonly string[] = [
  '05d15a28-3ef6-4aaf-aa29-9c037cd0b555', // elgrablidudu@gmail.com (Google)
  '0d2f3e72-c693-4ee9-9fbc-fa132c1c264a', // info@plto.app (Google)
];

export function isPltoAdmin(userId: string | null | undefined): boolean {
  return typeof userId === 'string' && PLTO_ADMIN_USER_IDS.includes(userId);
}
