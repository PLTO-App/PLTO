#!/bin/bash
# מריץ את בדיקות 126 ו-127 מול Postgres מקומי וזמני. אין קשר לשום מסד נתונים אחר.
# שימוש: PGHOST=<תיקיית socket> plans/drafts/tests/run-local.sh   (מהשורש של הריפו)
set -euo pipefail
: "${PGHOST:?יש להגדיר PGHOST לתיקיית ה-socket של Postgres מקומי}"
DB=plto_stage2_test
psql -U postgres -d postgres -qAt -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
psql -U postgres -d $DB -v ON_ERROR_STOP=1 -q -f plans/drafts/tests/00_stub_schema.sql
OUT=$(psql -U postgres -d $DB -v ON_ERROR_STOP=1 -q -At -f plans/drafts/tests/126_127.test.sql 2>&1 || true)
echo "$OUT" | sed -E 's/^psql:[^ ]+ NOTICE: +//' | grep -E '^(עבר|נכשל|===|---|psql:.*ERROR|ERROR)' || true
PASSED=$(echo "$OUT" | grep -c 'NOTICE:  עבר' || true)
echo "עברו $PASSED בדיקות"
psql -U postgres -d postgres -qAt -c "DROP DATABASE $DB"
