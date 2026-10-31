#!/usr/bin/env bash
# Installs the pre-commit hook of this clone (hooks are not part of Git, so run this at the start of every session).
set -eu
root=$(git rev-parse --show-toplevel)
cat > "$root/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/game-prototype/tools/check_no_secrets.sh"
HOOK
chmod +x "$root/.git/hooks/pre-commit" "$root/game-prototype/tools/check_no_secrets.sh"
echo "pre-commit hook installed"
