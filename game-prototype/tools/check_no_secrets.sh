#!/usr/bin/env bash
# Stops a commit that carries signing keys, packaged builds or credentials. Used by the git pre-commit hook
# (tools/install_git_hooks.sh) and can be run by hand: tools/check_no_secrets.sh [--all]  (--all checks every tracked file).
set -u
if [ "${1:-}" = "--all" ]; then files=$(git ls-files); else files=$(git diff --cached --name-only --diff-filter=ACMR); fi
bad=0
name_re='(\.keystore|\.jks|\.p12|\.pfx|\.pem|\.key|\.apk|\.aab|\.idsig)$|(^|/)(keystore|signing-notes|plto-secure)'
for f in $files; do
  if echo "$f" | grep -qiE "$name_re"; then echo "BLOCKED (file name looks like a key or a build): $f"; bad=1; continue; fi
  [ -f "$f" ] || continue
  case "$f" in *tools/check_no_secrets.sh) continue ;; esac   # this file names the patterns it looks for
  if grep -IqE 'BEGIN (RSA |EC |)PRIVATE KEY|debug_keystore_pass *= *"[^"]+"|--ks-pass|storepass[ =:]+[^ ]' "$f" 2>/dev/null; then echo "BLOCKED (content looks like a signing secret): $f"; bad=1; fi
done
[ "$bad" = 0 ] && echo "no secrets found" && exit 0
echo "Remove these from the commit. Keys live in the private folder, never in Git (see plans/game-signing-key-howto.md)."; exit 1
