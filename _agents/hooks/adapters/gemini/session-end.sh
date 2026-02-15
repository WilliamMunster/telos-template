#!/bin/bash
# Gemini CLI adapter for SessionEnd
# Parses Gemini's JSON stdin (reason field), logs to daily note

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/../../lib/session-logger.sh"

INPUT=""
if read -t 1 -r INPUT; then : ; else exit 0; fi

SUMMARY=$(python3 - "$INPUT" << 'PYEOF'
import sys, json
try:
    data = json.loads(sys.argv[1])
    reason = data.get("reason", "")
    if reason: print(f"Session ended: {reason}")
except: pass
PYEOF
)

session_log_end "$SUMMARY"
exit 0
