#!/bin/bash
# telos PostToolUse hook — tracks file changes after Write/Edit
# Logs file modifications to daily note for work trail
# Runs async to avoid blocking Claude's workflow

HOOK_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
HOOK_DIR="$(cd "$HOOK_DIR" 2>/dev/null && pwd || echo "$HOOK_DIR")"

source "$HOOK_DIR/../../lib/vault.sh"

# Read JSON input from stdin
INPUT=""
if read -t 1 -r INPUT; then
  : # got input
else
  exit 0
fi

# Extract tool info and decide what to log
PARSED=$(python3 << 'PYEOF' "$INPUT"
import sys, json, os

try:
    data = json.loads(sys.argv[1])
    tool_name = data.get('tool_name', '')
    tool_input = data.get('tool_input', {})

    # Only track Write and Edit operations
    if tool_name not in ('Write', 'Edit'):
        sys.exit(0)

    file_path = tool_input.get('file_path', '')
    if not file_path:
        sys.exit(0)

    # Skip tracking changes to hook scripts and settings (meta-noise)
    skip_patterns = [
        '.claude/hooks/',
        '.claude/settings',
        'settings.local.json',
    ]
    for pattern in skip_patterns:
        if pattern in file_path:
            sys.exit(0)

    # Get relative path from vault root
    vault_root = os.environ.get('CLAUDE_PROJECT_DIR', '')
    if vault_root and file_path.startswith(vault_root):
        rel_path = file_path[len(vault_root):].lstrip('/')
    else:
        rel_path = os.path.basename(file_path)

    # Line 1: raw file path (for frontmatter update)
    print(file_path)
    # Line 2: log entry
    if tool_name == 'Write':
        print(f"[file-created] {rel_path}")
    elif tool_name == 'Edit':
        print(f"[file-edited] {rel_path}")

except Exception:
    pass
PYEOF
)

if [ -z "$PARSED" ]; then
  exit 0
fi

FILE_PATH=$(echo "$PARSED" | head -1)
LOG_ENTRY=$(echo "$PARSED" | tail -1)

# --- Auto-update _telos/ frontmatter 'updated' field ---
update_telos_frontmatter() {
  local fpath="$1"
  # Only process _telos/*.md files
  case "$fpath" in
    */_telos/*.md) ;;
    *) return 0 ;;
  esac
  [ -f "$fpath" ] || return 0

  local has_fm
  has_fm=$(head -1 "$fpath")
  [ "$has_fm" = "---" ] || return 0
  grep -q '^updated:' "$fpath" || return 0

  local today
  today=$(date +%Y-%m-%d)
  local current
  current=$(grep '^updated:' "$fpath" | head -1 | sed 's/^updated:[[:space:]]*//')
  [ "$current" = "$today" ] && return 0

  # Update the field (portable sed -i)
  _sed_i "s/^updated:.*$/updated: ${today}/" "$fpath"
}

update_telos_frontmatter "$FILE_PATH"

TIMESTAMP=$(date +%H:%M)
ENTRY="- ${TIMESTAMP} ${LOG_ENTRY}"

vault_daily_append "$ENTRY"

exit 0
