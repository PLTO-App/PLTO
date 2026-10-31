# מפתח החתימה של PLTO Virtual: איפה הוא ואיך משתמשים בו

**המסמך הזה לא מכיל סיסמאות ולא את המפתח. הוא רק מסביר איפה הם ואיך להפעיל אותם.**

## למה זה חשוב
אפליקציית Android מתעדכנת רק אם העדכון חתום **באותו מפתח** והגרסה (`versionCode`) גבוהה יותר. אם נחתום במפתח אחר, הטלפון יסרב לעדכן, וההתקנה מחדש תמחק את השמירות. לכן **אסור ליצור מפתח חדש כל עוד המפתח הקיים קיים או אפשר להשיג אותו מדוד.**

## מה המפתח
- **אפליקציה:** `app.plto.virtual` (PLTO Virtual, מ-0.6.0). המשחק הישן `app.plto.noabakery` משתמש במפתח אחר, מקורי, שנמצא אצל דוד בלבד ולא נגענו בו.
- **סוג:** debug keystore של Godot, RSA 2048, תקף עד 2054-03-17, נוצר ב-30.10.2026.
- **שם הקובץ:** `plto-virtual-debug.keystore`. **alias:** `androiddebugkey`.
- **טביעת אצבע של התעודה (SHA-256, ציבורית ונראית בתוך כל APK):**
  `4A:FB:2D:6C:DA:67:29:81:1D:F5:BE:E9:68:FB:99:E0:02:EE:CB:AB:A0:3B:A7:93:76:B5:34:3C:67:3E:A8:4F`
  כל APK חתום נכון חייב להראות בדיוק אותה טביעה.

## איפה הוא נשמר
1. **עותק עבודה בסביבה:** `/root/.plto-secure/plto-virtual/` (תיקייה בהרשאה 700, קבצים בהרשאה 600), מחוץ לריפו. בתוכה `plto-virtual-debug.keystore` ו-`NOTES.txt` עם הסיסמה וה-alias. **סביבת הענן זמנית ונמחקת בין סשנים, ולכן זה לא העותק הקבוע.**
2. **עותק קבוע: אצל דוד.** שני הקבצים נשלחו אליו בסוף הסשן. שם הם מתגוננים ממחיקה של הסביבה. דוד צריך לשמור אותם במקום מאובטח (לא ב-Git, לא בצ'אט ציבורי).
3. **ב-Git: כלום.** לא המפתח, לא הסיסמה ולא קבצי APK.

## בתחילת כל סשן שבונה APK
1. בדקו אם `/root/.plto-secure/plto-virtual/plto-virtual-debug.keystore` קיים. אם לא (סשן חדש), **בקשו מדוד להעלות את שני הקבצים** (המפתח ו-`NOTES.txt`) לסשן, ושימו אותם שם (`mkdir -p` עם הרשאה 700, הקבצים 600).
2. התקינו את מגן הסודות (הוקים לא נשמרים ב-Git): `game-prototype/tools/install_git_hooks.sh`.
3. כוונו את Godot למפתח (הסיסמה נקראת מהסביבה, לא מקובץ בריפו):
   ```
   PLTO_KEY_PASS='<הסיסמה מתוך NOTES.txt>' \
   PLTO_ANDROID_SDK=<נתיב ה-SDK> PLTO_JAVA_HOME=<נתיב ה-JDK> \
   game-prototype/tools/use_signing_key.sh /root/.plto-secure/plto-virtual/plto-virtual-debug.keystore androiddebugkey
   ```
4. התקינו כלים מהמקורות הרשמיים ובדקו סכומים (Godot 4.5.1, תבניות ייצוא, Android cmdline-tools, build-tools 35.0.1, platform android-35).
5. העלו `version/code` ב-`game-prototype/export_presets.cfg` (חייב להיות גבוה מהקודם, כרגע 1 ב-0.6.0) ושם גרסה, ואז: `godot --headless --path game-prototype --import`, `python3 -I game-prototype/tools/patch_imports.py game-prototype`, `godot --headless --path game-prototype --export-debug "Android Debug" <נתיב>.apk`.
6. **אימות לפני מסירה:** `apksigner verify --print-certs <apk>` חייב להציג את טביעת האצבע שלמעלה, ו-`aapt2 dump badging` חייב להציג `app.plto.virtual` ו-`versionCode` גבוה מהקודם. אחרי הבנייה להחזיר את קבצי `.import` שנוצרו בייצוא (`git checkout`).

## הגנות מפני העלאה בטעות
- `.gitignore` בשורש ובתיקיית המשחק חוסם `*.keystore`, `*.jks`, `*.p12`, `*.pfx`, `*.pem`, `*.key`, `*.apk`, `*.aab`, `*.idsig`, וקבצים בשם `*signing-notes*` או `plto-secure`.
- **הוק pre-commit** (`tools/check_no_secrets.sh`) חוסם גם קבצים שנוספו בכוח (`git add -f`) וגם תוכן שנראה כמו סיסמת חתימה או מפתח פרטי. נבדק בפועל: קובץ keystore שהוכנס בכוח נחסם. אפשר להריץ ידנית: `tools/check_no_secrets.sh --all`.
- הוקים לא חלק מ-Git, ולכן **מריצים `install_git_hooks.sh` בכל סשן**. גם בלי ההוק, ה-`.gitignore` ממשיך להגן.

## אם המפתח אבד
אין דרך לשחזר אותו. האפשרויות: (א) להתקין גרסה חדשה כאפליקציה חדשה, בלי העברת שמירות, עם `app.plto.virtual2` או מפתח חדש לאותו מזהה (הטלפון יבקש הסרה, והשמירות נמחקות), (ב) להמשיך לבנות רק בדיקות חדשות. לכן חשוב לשמור את שני הקבצים אצל דוד.

## ההבדל מ"חתימה אמיתית"
זה debug key: מתאים לבדיקה אישית ולהתקנה ישירה. להפצה בחנות (Google Play) נחוץ מפתח release נפרד שנוצר בכוונה, סיסמה חזקה ושמירה מגובה, ואז אפשר להשתמש ב-Play App Signing. זה לא נדרש כרגע.
