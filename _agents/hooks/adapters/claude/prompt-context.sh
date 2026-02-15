#!/bin/bash
# telos UserPromptSubmit hook
# Detects keywords in user prompt and injects relevant vault context
# Must be fast — runs on every message. Fail-open design.

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

# Check Obsidian running
if ! vault_available; then
  exit 0
fi

# Extract user prompt text
PROMPT=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    print(data.get('userMessage', ''))
except:
    pass
" "$INPUT" 2>/dev/null)

if [ -z "$PROMPT" ]; then
  exit 0
fi

# Quick keyword detection via Python — returns search terms or empty
SEARCH_TERMS=$(echo "$PROMPT" | python3 << 'PYEOF'
import sys, re

prompt = sys.stdin.read().lower()

# Skip very short prompts or simple confirmations
if len(prompt) < 5 or prompt.strip() in ['y', 'n', 'yes', 'no', 'ok', '1', '2', '3', '4']:
    sys.exit(0)

# Project keywords -> search terms
# Customize this map with your own project names and keywords
keyword_map = {
    'telos': 'telos',
    'okr': 'goals',
    'goal': 'goals',
    'decision': 'beliefs',
    'lesson': 'lessons',
    'project': 'projects',
}

matches = set()
for keyword, search_term in keyword_map.items():
    if keyword in prompt:
        matches.add(search_term)

# Max 2 search terms to keep it fast
for term in list(matches)[:2]:
    print(term)
PYEOF
)

if [ -z "$SEARCH_TERMS" ]; then
  exit 0
fi

# Search vault for each term, collect results
CONTEXT=""
while IFS= read -r term; do
  [ -z "$term" ] && continue

  RESULT=$($OBS search query="$term" limit=3 matches 2>&1 &
  PID=$!; sleep 3; kill $PID 2>/dev/null; wait $PID 2>/dev/null)

  # Filter CLI noise
  RESULT=$(echo "$RESULT" | vault_filter_noise | head -20)

  if [ -n "$RESULT" ]; then
    CONTEXT="${CONTEXT}\n### Vault context for '${term}':\n${RESULT}\n"
  fi
done <<< "$SEARCH_TERMS"

if [ -z "$CONTEXT" ]; then
  exit 0
fi

# Output context as JSON
CONTEXT_ESCAPED=$(echo -e "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":${CONTEXT_ESCAPED}}}
EOF

exit 0
