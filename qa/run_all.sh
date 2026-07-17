#!/usr/bin/env bash
# בדיקה מקיפה שבועית — מריץ syntax check + 3 בדיקות Playwright offline.
# הרצה: bash qa/run_all.sh  (מתיקיית שורש הריפו)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
FAIL=0

echo "=== syntax check (כל בלוקי ה-script, כל הדפים) ==="
node qa/check_syntax.js index.html admin.html landing.html sign.html privacy-policy.html || FAIL=1

echo ""
echo "=== qa_index.js ==="
node qa/qa_index.js || FAIL=1

echo ""
echo "=== qa_admin.js ==="
node qa/qa_admin.js || FAIL=1

echo ""
echo "=== qa_landing.js ==="
node qa/qa_landing.js || FAIL=1

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ כל הבדיקות עברו"
else
  echo "❌ יש בדיקות שנכשלו, ראה למעלה"
fi
exit $FAIL
