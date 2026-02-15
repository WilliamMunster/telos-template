#!/bin/bash
# telos Notification hook — routes Claude Code notifications to desktop
# Sends system notifications for permission prompts and idle alerts

HOOK_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
HOOK_DIR="$(cd "$HOOK_DIR" 2>/dev/null && pwd || echo "$HOOK_DIR")"

# Read JSON input from stdin
INPUT=""
if read -t 1 -r INPUT; then
  : # got input
else
  exit 0
fi

# Extract notification type and message
NOTIFY_INFO=$(python3 << 'PYEOF' "$INPUT"
import sys, json

try:
    data = json.loads(sys.argv[1])
    ntype = data.get('notification_type', '')
    message = data.get('message', '')

    # Map notification types to user-friendly titles
    titles = {
        'permission_prompt': 'Authorization needed',
        'idle_prompt': 'Waiting for input',
        'auth_success': 'Auth success',
        'elicitation_dialog': 'Question for you',
    }

    title = titles.get(ntype, '')
    if not title:
        sys.exit(0)

    # Truncate long messages
    if len(message) > 200:
        message = message[:197] + '...'

    print(f"{title}\n{message}")

except Exception:
    pass
PYEOF
)

if [ -z "$NOTIFY_INFO" ]; then
  exit 0
fi

TITLE=$(echo "$NOTIFY_INFO" | head -1)
BODY=$(echo "$NOTIFY_INFO" | tail -n +2)

# macOS-only notification
if [[ "$OSTYPE" == darwin* ]]; then
  osascript -e "display notification \"$BODY\" with title \"telos\" subtitle \"$TITLE\" sound name \"Tink\"" 2>/dev/null
# Linux notification via notify-send
elif [[ "$OSTYPE" == linux* ]] && command -v notify-send &>/dev/null; then
  notify-send "telos: $TITLE" "$BODY" 2>/dev/null
fi

exit 0
