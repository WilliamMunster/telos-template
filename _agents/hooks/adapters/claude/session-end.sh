#!/bin/bash
# Claude Code adapter for Stop (session end)
# Parses Claude's JSON stdin, extracts summary, calls shared session-logger

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/../../lib/session-logger.sh"

INPUT=""
if read -t 1 -r INPUT; then : ; else exit 0; fi

SUMMARY=$(python3 - "$INPUT" << 'PYEOF'
import sys, json
try:
    data = json.loads(sys.argv[1])
    summary = data.get("transcript_summary", "")
    stop_reason = data.get("stop_hook_reason", "")
    parts = []
    if summary: parts.append(summary)
    if stop_reason: parts.append(f"Stop: {stop_reason}")
    if parts: print(" | ".join(parts))
except: pass
PYEOF
)

session_log_end "$SUMMARY"
session_check_telos_consistency
exit 0
