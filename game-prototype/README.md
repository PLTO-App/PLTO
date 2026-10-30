# רחוב הגפן: המאפייה של נועה (אבטיפוס משחק)

פרויקט Godot 4.5.1 (רנדרר Compatibility) למשחק הסימולציה העסקי של PLTO. הפרויקט נפרד לגמרי ממערכת ה-CRM: אין בו חיבור ל-Supabase, אין נתוני משתמשים ואין הרשאות רשת.

## מה יש בגרסה 0.5
רחוב עם שישה בניינים: המאפייה של נועה, בית קפה (נפתח בהמשך), המכולת של אבי, משרד הנהלת חשבונות, בנק ומחסן ספקים. בכל בוקר יש משלוחים, חשבוניות ואירועים, אחר כך רשימת "היום" ותכנון לכל עסק. במהלך היום נועה משרתת בעסק אחד והעובדים בשני. בערב מוצגים סיכום, רווח והפסד ומטרות, ובסוף השבוע מגיע דוח שבועי. פירוט נמצא ב-`plans/game-v0-5-status-2026-10-29.md`.

## שכבות
| שכבה | נתיב | אחריות |
|---|---|---|
| תוכן | `content/` | עולם (`world.json`), עסקים (`businesses/*.json`), אירועים, מטרות, דרגות. כל הטקסטים הם מפתחות תרגום |
| טקסטים | `locale/strings.csv`, `locale/formats.json` | עמודה לכל שפה (עברית היא ברירת המחדל), כיווניות ופורמט כסף לכל שפה |
| מנוע | `scripts/sim/` | `company.gd` (החברה, היום, השבוע), `business.gd`, `day_runner.gd`, `demand.gd`, `inventory.gd`, `ledger.gd`, `events.gd`, `goals.gd`, `coach.gd`. בלי מסך ובלי תלת־ממד |
| ליבה | `scripts/core/` | `game.gd` (autoload: שמירה והגדרות), `loc.gd` (תרגום ופורמטים), `content_db.gd`, `profile.gd`, `save_store.gd`, `sfx.gd` |
| עולם | `scripts/world/` | `town.gd` (הרחוב), `shop_room.gd` (פנים העסקים), `character_rig.gd` (הדמויות), `npc.gd`, `player.gd` |
| ממשק | `scripts/ui/` | `game_ui.gd`, `hud.gd`, `sheet.gd`, `screens.gd`, `reward_fx.gd`, `ui_style.gd`, `ui_icons.gd`, `fonts.gd` |
| מהלך | `scripts/main.gd` | בוקר ברחוב, יום בעסק, סגירה וערב |

כל הכסף במספרים שלמים בשקלים. המספרים להמחשה בלבד, ואינם ייעוץ עסקי, פיננסי, משפטי או מס.

## נכסים (הכול יצירה מקורית מקוד)
- `tools/blender/make_characters.py`: דמויות עם שלד, שיער, אביזרים ו-14 אנימציות. `tools/make_faces.py`: אטלס הבעות הפנים.
- `tools/blender/make_town.py`: בנייני הרחוב והאביזרים. `tools/blender/make_interiors.py`: רהיטים, מאפים וחומרי גלם. `tools/blender/kit.py`: עזרי מידול.
- `tools/make_music.py`: מוזיקה, אווירה וצלילים. `tools/make_sounds.py`: צלילי מגע ומטבעות. `tools/make_icons.py`: בועה וצל.
- `dev/make_portraits.tscn`: דיוקנאות ואייקונים מתוך המודלים. `dev/make_icon.tscn`: אייקון האפליקציה.
- `tools/locale_tool.py`: הוספת מפתחות תרגום ובדיקה שלא חסר טקסט.

## בדיקות
```
godot --headless --path . --script dev/test_sim.gd              # מנוע ואיזון (כולל מינימרקט ומסלול בעל עסק): 146 בדיקות וסימולציה של 6 שבועות
godot --headless --path . --script dev/sim_owner.gd -- grid     # איזון מסלול בעל עסק (גם: sweep, setup, long, baseline)
godot --headless --path . res://dev/test_save.tscn              # שמירה, טעינה ושמירה מגרסה 0.4
godot --headless --path . --script dev/test_saveload.gd         # שמירה וטעינה בכל בוקר וערב לא משנות את מהלך המשחק (5 עונות)
xvfb-run -a godot --path . --rendering-driver opengl3 res://dev/layout_audit.tscn -- out=/tmp/audit shots=flagged   # פריסה ב-18 גדלי מסך, לאורך ולרוחב (כ-12 דקות)
godot --headless --path . res://dev/check_scene.tscn            # כל הסקריפטים מתקמפלים
xvfb-run -a godot --path . --rendering-driver opengl3 res://scenes/main.tscn -- --autotest fast=2 days=5 out=/tmp/shots [size=360x640] [landscape=1] [market=1]
python3 -I tools/locale_tool.py . check                         # אין מפתח טקסט חסר
```

## בניית APK (debug)
דרישות: Godot 4.5.1 עם תבניות הייצוא, JDK, Android SDK (platform-tools, build-tools 35.0.1, platforms;android-35), ומפתח ה-debug המקורי מוגדר בהגדרות העורך (`export/android/debug_keystore`). המפתח לא נשמר ב-Git.
```
godot --headless --path . --import
godot --headless --path . --export-debug "Android Debug" build/noa-bakery-debug.apk
```

## כללים
- נכס חיצוני נכנס רק עם רישיון ברור ואימות מול מקור רשמי. כרגע הנכס החיצוני היחיד הוא הגופן Noto (חבילת Ubuntu חתומה).
- אין שירותי רשת, אנליטיקס או הרשאות באפליקציה.
