"""
Security Guardian Agent — מלי יופי ועור CRM
סוכן AI אקטיבי לאבטחת נתוני לקוחות רגישים.

הפעלה:  python agents/security-agent.py
        python agents/security-agent.py --mode full
        python agents/security-agent.py --mode secrets
        python agents/security-agent.py --mode rls
        python agents/security-agent.py --mode logs
"""

import os
import re
import json
import asyncio
import subprocess
from datetime import datetime
from pathlib import Path
import anthropic

# ── Config ──────────────────────────────────────────────────────────────────
SUPABASE_URL        = os.getenv("NEXT_PUBLIC_SUPABASE_URL", "")
SUPABASE_ANON_KEY   = os.getenv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_KEY= os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
MAKE_ALERT_WEBHOOK  = os.getenv("MAKE_SECURITY_ALERT_WEBHOOK", "")
ANTHROPIC_API_KEY   = os.getenv("ANTHROPIC_API_KEY", "")

PROJECT_ROOT = Path(__file__).parent.parent

# סוגי אירועים שמחייבים התראה מיידית
CRITICAL_PATTERNS = [
    r"sk-ant-[a-zA-Z0-9\-_]{20,}",          # Anthropic API key
    r"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",# Supabase JWT
    r"service_role",                          # service role key
    r"1234",                                  # default PIN
]

# ── Tools Definition (Claude tool_use) ──────────────────────────────────────
SECURITY_TOOLS = [
    {
        "name": "scan_secrets",
        "description": "סרוק את כל קבצי הפרויקט לאיתור סודות חשופים (API keys, passwords, tokens)",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "נתיב לסריקה (default: כל הפרויקט)"},
                "patterns": {"type": "array", "items": {"type": "string"}, "description": "regex patterns לחיפוש"}
            }
        }
    },
    {
        "name": "audit_rls_policies",
        "description": "בדוק RLS policies על כל טבלאות Supabase — ודא שכולן מוגנות",
        "input_schema": {
            "type": "object",
            "properties": {
                "tables": {"type": "array", "items": {"type": "string"}, "description": "רשימת טבלאות לבדיקה"}
            }
        }
    },
    {
        "name": "check_audit_log",
        "description": "בדוק לוג ביקורת לאיתור פעילות חשודה: מחיקות מרובות, שינויי מחיר, גישת admin חריגה",
        "input_schema": {
            "type": "object",
            "properties": {
                "hours": {"type": "number", "description": "כמה שעות אחורה לבדוק (default: 24)"},
                "severity": {"type": "string", "enum": ["all", "critical", "warning"]}
            }
        }
    },
    {
        "name": "validate_admin_auth",
        "description": "בדוק הגדרות אבטחת admin: PIN strength, brute force protection, session timeout",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "check_pii_exposure",
        "description": "בדוק שנתוני לקוחות רגישים (טלפון, שם, עור) לא נחשפים בלוגים, errors, או console",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "קובץ לבדיקה (default: index.html)"}
            }
        }
    },
    {
        "name": "send_security_alert",
        "description": "שלח התראת אבטחה דחופה למלי דרך WhatsApp",
        "input_schema": {
            "type": "object",
            "properties": {
                "severity": {"type": "string", "enum": ["critical", "warning", "info"]},
                "title": {"type": "string"},
                "details": {"type": "string"},
                "action_required": {"type": "string"}
            },
            "required": ["severity", "title", "details"]
        }
    },
    {
        "name": "generate_security_report",
        "description": "צור דוח אבטחה מקיף עם ציון, ממצאים, והמלצות",
        "input_schema": {
            "type": "object",
            "properties": {
                "findings": {"type": "array", "items": {"type": "object"}},
                "output_format": {"type": "string", "enum": ["summary", "full", "json"]}
            }
        }
    }
]

# ── Tool Implementations ─────────────────────────────────────────────────────

def scan_secrets(path: str = None, patterns: list = None) -> dict:
    """סרוק קבצים לאיתור secrets חשופים."""
    scan_path = Path(path) if path else PROJECT_ROOT
    check_patterns = patterns or CRITICAL_PATTERNS
    findings = []

    # קבצים לסריקה
    skip_dirs = {".git", "node_modules", "__pycache__", ".venv", "venv"}
    skip_files = {"storage_state.json", "*.min.js"}

    for file_path in scan_path.rglob("*"):
        if not file_path.is_file():
            continue
        if any(d in file_path.parts for d in skip_dirs):
            continue
        if file_path.suffix in {".png", ".jpg", ".ico", ".woff", ".woff2"}:
            continue

        try:
            content = file_path.read_text(encoding="utf-8", errors="ignore")
            for pattern in check_patterns:
                matches = re.findall(pattern, content)
                if matches:
                    # חשב שורה
                    for i, line in enumerate(content.split("\n"), 1):
                        if re.search(pattern, line):
                            findings.append({
                                "file": str(file_path.relative_to(PROJECT_ROOT)),
                                "line": i,
                                "pattern": pattern,
                                "severity": "critical",
                                "preview": line.strip()[:80] + "..."
                            })
        except Exception:
            continue

    return {
        "status": "critical" if findings else "clean",
        "findings": findings,
        "files_scanned": sum(1 for _ in scan_path.rglob("*") if _.is_file()),
        "timestamp": datetime.now().isoformat()
    }


def audit_rls_policies(tables: list = None) -> dict:
    """בדוק RLS policies ב-Supabase."""
    if not SUPABASE_SERVICE_KEY:
        return {"status": "skipped", "reason": "SUPABASE_SERVICE_ROLE_KEY לא מוגדר"}

    required_tables = tables or ["bookings", "clients", "services", "schedule", "audit_log"]
    results = []

    try:
        import httpx
        headers = {
            "apikey": SUPABASE_SERVICE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
            "Content-Type": "application/json"
        }

        # בדוק RLS status
        sql = """
        SELECT tablename, rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public'
        ORDER BY tablename;
        """
        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/rpc/exec_sql",
            headers=headers,
            json={"sql": sql},
            timeout=10
        )

        for table in required_tables:
            results.append({
                "table": table,
                "rls_enabled": None,  # יוחלף בתוצאה אמיתית
                "policies_count": None,
                "status": "unknown"
            })

    except Exception as e:
        return {"status": "error", "error": str(e)}

    return {"status": "checked", "tables": results}


def check_audit_log(hours: int = 24, severity: str = "all") -> dict:
    """בדוק לוג ביקורת לפעילות חשודה."""
    suspicious_patterns = []

    # בדוק git log לשינויים חשודים
    try:
        result = subprocess.run(
            ["git", "-C", str(PROJECT_ROOT), "log", "--oneline", f"--since={hours} hours ago"],
            capture_output=True, text=True, timeout=10
        )
        commits = result.stdout.strip().split("\n") if result.stdout.strip() else []

        for commit in commits:
            if any(kw in commit.lower() for kw in ["delete", "remove", "password", "secret", "key"]):
                suspicious_patterns.append({
                    "type": "suspicious_commit",
                    "detail": commit,
                    "severity": "warning"
                })
    except Exception:
        pass

    return {
        "status": "checked",
        "hours_checked": hours,
        "suspicious_patterns": suspicious_patterns,
        "alert_count": len(suspicious_patterns)
    }


def validate_admin_auth() -> dict:
    """בדוק הגדרות אבטחת admin."""
    issues = []
    index_path = PROJECT_ROOT / "index.html"

    if index_path.exists():
        content = index_path.read_text(encoding="utf-8", errors="ignore")

        # בדוק PIN default
        if "'1234'" in content or '"1234"' in content:
            issues.append({
                "issue": "PIN ברירת מחדל '1234' — חייב להחליף!",
                "severity": "critical",
                "fix": "שנה ל-PIN חזק ב-SalonSettings ב-Supabase"
            })

        # בדוק hash
        if "hashPin" not in content and "sha" not in content.lower():
            issues.append({
                "issue": "PIN לא מוצפן (hash) — מאוחסן כטקסט גלוי",
                "severity": "critical",
                "fix": "הוסף hashPin() לפני שמירה ולפני השוואה"
            })

        # בדוק brute force protection
        if "lockout" not in content.lower() and "attempts" not in content.lower():
            issues.append({
                "issue": "אין הגנת brute-force — ניתן לנסות PIN ללא הגבלה",
                "severity": "high",
                "fix": "הוסף מונה ניסיונות + lockout אחרי 5 כשלונות"
            })

        # בדוק session timeout
        if "setTimeout" not in content or "session" not in content.lower():
            issues.append({
                "issue": "אין session timeout — admin נשאר מחובר לנצח",
                "severity": "medium",
                "fix": "הוסף logout אוטומטי אחרי 30 דקות חוסר פעילות"
            })

    return {
        "status": "critical" if any(i["severity"] == "critical" for i in issues) else
                  "warning" if issues else "clean",
        "issues": issues,
        "total_issues": len(issues)
    }


def check_pii_exposure(file_path: str = None) -> dict:
    """בדוק חשיפת PII בקוד."""
    check_file = Path(file_path) if file_path else PROJECT_ROOT / "index.html"
    issues = []

    if not check_file.exists():
        return {"status": "error", "reason": "קובץ לא נמצא"}

    content = check_file.read_text(encoding="utf-8", errors="ignore")
    lines = content.split("\n")

    pii_patterns = [
        (r"console\.log.*phone", "מספר טלפון נחשף ב-console.log", "high"),
        (r"console\.log.*client_name", "שם לקוחה נחשף ב-console.log", "medium"),
        (r"console\.log.*skin_type", "נתון רפואי נחשף ב-console.log", "critical"),
        (r"innerHTML.*phone", "מספר טלפון ב-innerHTML (XSS risk)", "high"),
        (r"alert\(.*phone", "מספר טלפון ב-alert()", "medium"),
        (r"localStorage.*client", "נתוני לקוחות ב-localStorage", "high"),
    ]

    for i, line in enumerate(lines, 1):
        for pattern, description, severity in pii_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                issues.append({
                    "line": i,
                    "issue": description,
                    "severity": severity,
                    "code": line.strip()[:100]
                })

    return {
        "status": "issues_found" if issues else "clean",
        "issues": issues,
        "file": str(check_file.relative_to(PROJECT_ROOT))
    }


def send_security_alert(severity: str, title: str, details: str, action_required: str = None) -> dict:
    """שלח התראה דרך Make.com webhook."""
    if not MAKE_ALERT_WEBHOOK:
        # Fallback: שמור ב-לוג מקומי
        alert = {
            "timestamp": datetime.now().isoformat(),
            "severity": severity,
            "title": title,
            "details": details,
            "action_required": action_required
        }
        log_path = PROJECT_ROOT / "security-alerts.log"
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(alert, ensure_ascii=False) + "\n")
        return {"status": "logged_locally", "file": "security-alerts.log"}

    severity_emoji = {"critical": "🚨", "warning": "⚠️", "info": "ℹ️"}
    message = f"""
{severity_emoji.get(severity, '🔒')} *{title}*

{details}
{f'⚡ נדרש: {action_required}' if action_required else ''}

🕐 {datetime.now().strftime('%d/%m/%Y %H:%M')}
Security Guardian — מלי CRM
    """.strip()

    try:
        import httpx
        httpx.post(MAKE_ALERT_WEBHOOK, json={"message": message, "severity": severity}, timeout=5)
        return {"status": "sent", "severity": severity}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def generate_security_report(findings: list, output_format: str = "full") -> dict:
    """צור דוח אבטחה מסכם."""
    critical = [f for f in findings if f.get("severity") == "critical"]
    high     = [f for f in findings if f.get("severity") == "high"]
    medium   = [f for f in findings if f.get("severity") == "medium"]

    # ציון 0-100
    score = 100
    score -= len(critical) * 25
    score -= len(high) * 10
    score -= len(medium) * 5
    score = max(0, score)

    grade = "A" if score >= 90 else "B" if score >= 75 else "C" if score >= 60 else "D" if score >= 40 else "F"

    report = {
        "timestamp": datetime.now().isoformat(),
        "score": score,
        "grade": grade,
        "summary": {
            "critical": len(critical),
            "high": len(high),
            "medium": len(medium),
            "total": len(findings)
        },
        "findings": findings if output_format == "full" else [],
        "top_priority": critical[0] if critical else (high[0] if high else None),
        "status": "FAIL" if score < 60 else "PASS"
    }

    # שמור דוח
    report_path = PROJECT_ROOT / f"security-report-{datetime.now().strftime('%Y%m%d-%H%M')}.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    return report


# ── Tool Router ──────────────────────────────────────────────────────────────

def execute_tool(tool_name: str, tool_input: dict) -> str:
    tools_map = {
        "scan_secrets":         scan_secrets,
        "audit_rls_policies":   audit_rls_policies,
        "check_audit_log":      check_audit_log,
        "validate_admin_auth":  validate_admin_auth,
        "check_pii_exposure":   check_pii_exposure,
        "send_security_alert":  send_security_alert,
        "generate_security_report": generate_security_report,
    }

    fn = tools_map.get(tool_name)
    if not fn:
        return json.dumps({"error": f"Tool {tool_name} not found"})

    try:
        result = fn(**tool_input)
        return json.dumps(result, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e), "tool": tool_name})


# ── Main Agent Loop ──────────────────────────────────────────────────────────

def run_security_agent(mode: str = "full"):
    """הפעל את סוכן האבטחה."""

    mode_prompts = {
        "full": """
בצע ביקורת אבטחה מקיפה של מערכת CRM מלי יופי ועור:

1. סרוק את כל הקבצים לאיתור secrets חשופים (API keys, passwords)
2. בדוק הגדרות אבטחת admin (PIN, brute force, session)
3. בדוק חשיפת נתוני לקוחות רגישים (PII) בקוד
4. בדוק לוג ביקורת לפעילות חשודה
5. בדוק RLS policies ב-Supabase
6. אם מצאת בעיות קריטיות — שלח התראה
7. צור דוח מסכם מלא עם ציון וסדר עדיפויות לתיקון

היה יסודי. המערכת מכילה נתוני לקוחות רפואיים רגישים (סוג עור, אלרגיות).
""",
        "secrets": "בצע סריקת secrets בלבד — חפש API keys, passwords, ו-tokens חשופים בכל קבצי הפרויקט.",
        "rls":     "בדוק בלבד את RLS policies ב-Supabase — ודא שכל הטבלאות מוגנות.",
        "logs":    "בדוק בלבד את לוג הביקורת לפעילות חשודה ב-24 שעות האחרונות.",
        "auth":    "בדוק בלבד את הגדרות האבטחה של admin — PIN, brute force, session timeout.",
        "pii":     "בדוק בלבד חשיפת נתוני לקוחות רגישים (PII) בקוד."
    }

    system_prompt = """
אתה Security Guardian Agent — סוכן אבטחה מומחה למערכת CRM של סלון יופי.

המערכת מכילה:
- נתוני לקוחות רגישים: שמות, טלפונים, מידע רפואי (סוג עור, אלרגיות)
- מפתחות API: Supabase, Anthropic, Make.com
- admin PIN לניהול המערכת

חוקי אבטחה קריטיים:
1. אין API key ב-git או בקוד — רק ב-.env.local
2. כל טבלת Supabase חייבת RLS
3. PIN חייב להיות מוצפן (hash), לא '1234'
4. נתוני לקוחות לא נחשפים ב-console.log
5. יש הגנת brute-force על admin login

דווח בעברית. סדר ממצאים לפי חומרה: critical → high → medium → low.
על כל ממצא קריטי — שלח התראה מיידית.
"""

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    messages = [{"role": "user", "content": mode_prompts.get(mode, mode_prompts["full"])}]

    print(f"\n🔒 Security Guardian Agent — מתחיל ביקורת ({mode})")
    print("=" * 55)

    while True:
        response = client.messages.create(
            model="claude-opus-4-8",
            max_tokens=4096,
            system=system_prompt,
            tools=SECURITY_TOOLS,
            messages=messages
        )

        # הוסף תגובה להיסטוריה
        messages.append({"role": "assistant", "content": response.content})

        # הצג טקסט
        for block in response.content:
            if hasattr(block, "text") and block.text:
                print(block.text)

        # אם אין tool use — סיים
        if response.stop_reason == "end_turn":
            break

        # הפעל tools
        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                print(f"\n🔧 מריץ: {block.name}...")
                result = execute_tool(block.name, block.input)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result
                })

        if tool_results:
            messages.append({"role": "user", "content": tool_results})
        else:
            break

    print("\n" + "=" * 55)
    print("✅ ביקורת הושלמה")


# ── Entry Point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    mode = "full"
    if len(sys.argv) > 1:
        arg = sys.argv[1].replace("--mode=", "").replace("--mode ", "").lstrip("-")
        if arg in ("full", "secrets", "rls", "logs", "auth", "pii"):
            mode = arg

    if not ANTHROPIC_API_KEY:
        print("❌ חסר ANTHROPIC_API_KEY ב-.env.local")
        sys.exit(1)

    run_security_agent(mode)
