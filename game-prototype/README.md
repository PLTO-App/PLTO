# המאפייה של נועה (אבטיפוס משחק)

פרויקט Godot 4.5.1 (רנדרר Compatibility) למשחק הסימולציה העסקי של PLTO. פרויקט נפרד לגמרי ממערכת ה-CRM: אין בו חיבור ל-Supabase, אין נתוני משתמשים ואין הרשאות רשת.

## מה יש בגרסה הנוכחית (0.2)
- המאפייה בתלת־ממד, עם התנגשויות בקירות ובריהוט.
- נועה (דמות זמנית שנבנית בקוד, ראו `scripts/noa_rig.gd`) עם אנימציות עמידה, הליכה, נשיאה והושטת יד.
- שליטה במגע: גרירה בצד שמאל של המסך (ג'ויסטיק צף), וכפתור פעולה שמופיע ליד חפץ.
- אינטראקציה אחת: לקחת עוגה מהדלפק ולהניח אותה על שולחן הלקוחות.
- ממשק בעברית, פורטרט ולנדסקייפ, עם כיבוד אזורי בטיחות (חריץ מצלמה).

## מבנה
| נתיב | תפקיד |
|---|---|
| `scripts/main.gd` | מהלך הפרק, מצלמה, סמן יעד |
| `scripts/bakery_room.gd` | בניית החדר והתנגשויות |
| `scripts/noa_rig.gd` | הגוף והאנימציות של נועה |
| `scripts/player.gd` | תנועה והתנגשות |
| `scripts/touch_ui.gd` | ג'ויסטיק, כפתור פעולה, כרטיסים |
| `scripts/game_state.gd` | דגלים ומדדים להשלכות עתידיות |
| `assets/` | דגמים וטקסטורות (CC0, מכווצים לטלפון), גופן, תמונות |
| `dev/autotest.gd` | בדיקה אוטומטית שמשחקת את הפרק (לא נכנסת ל-APK) |
| `tools/` | סקריפטים לשחזור הנכסים |

## הרצה ובדיקה על מחשב
```
godot --path game-prototype                                  # הרצה
godot --path game-prototype -- --autotest out=/tmp/shots     # משחק את הפרק לבד ושומר צילומים
godot --path game-prototype -- --autotest landscape=1 out=/tmp/shots
```
בלי מסך גרפי אפשר להריץ דרך `xvfb-run -a godot --rendering-driver opengl3 ...`. מקלדת: חצים להליכה, Enter לפעולה.

## בניית APK לבדיקה (debug)
דרישות: Godot 4.5.1 עם תבניות הייצוא שלו, JDK, Android SDK (platform-tools, build-tools 35.0.1, platforms;android-35), ומפתח debug מקומי שמוגדר בהגדרות העורך של Godot (`export/android/debug_keystore`). המפתח לא נשמר ב-Git.
```
godot --headless --path game-prototype --import
python3 -I game-prototype/tools/patch_imports.py game-prototype     # דחיסת טקסטורות לטלפון
godot --headless --path game-prototype --import
godot --headless --path game-prototype --export-debug "Android Debug" build/noa-bakery-debug.apk
```
הקובץ `build/` לא נכנס ל-Git.

## שחזור נכסים
הדגמים והטקסטורות כבר בתיקייה `assets/`. לשחזור מאפס: `tools/ph_download.py` מוריד מ-Poly Haven ומאמת כל קובץ מול ה-md5 שה-API שלהם מפרסם, `tools/prep_assets.py` ו-`tools/optimize_models.py` (Blender 4.2) מכווצים. פרטים והסברים בסעיף 7 של `plans/game-performance-test-2026-10-29.md`.

## כללים
- לא מוסיפים נכס שאי אפשר לאמת מול ערך רשמי של המקור. רישיון CC0 או רישיון מסחרי ברור שאומת באתר המקור.
- הגופן DejaVu Sans מצורף כי גופן ברירת המחדל של Godot אינו כולל עברית.
- אין שירותי רשת, אנליטיקס או הרשאות באפליקציה.
