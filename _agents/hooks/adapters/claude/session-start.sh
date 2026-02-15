#!/bin/bash
# Claude Code adapter for SessionStart
# Loads telos context from vault files, truncated to avoid timeout

VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
TELOS="$VAULT/_telos"
TODAY=$(date +%Y-%m-%d)
MAX_LINES=20

# Read file with truncation, strip frontmatter
read_truncated() {
  local file="$1"
  [ -f "$file" ] || return
  sed '/^---$/,/^---$/d' "$file" | head -n "$MAX_LINES"
}

CONTEXT="[telos context loaded]"

# Daily note
DAILY="$VAULT/_journal/daily/${TODAY}.md"
if [ -f "$DAILY" ]; then
  content=$(read_truncated "$DAILY")
  [ -n "$content" ] && CONTEXT="$CONTEXT\n\n## Today's Daily Note\n$content"
fi

# Telos files
for pair in "goals.md:Current Goals" "projects.md:Active Projects" "lessons.md:Recent Lessons" "worklog.md:Active Worklog"; do
  file="${pair%%:*}"
  heading="${pair#*:}"
  content=$(read_truncated "$TELOS/$file")
  [ -n "$content" ] && CONTEXT="$CONTEXT\n\n## $heading\n$content"
done

CONTEXT_ESCAPED=$(echo -e "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":${CONTEXT_ESCAPED}}}
EOF
exit 0
