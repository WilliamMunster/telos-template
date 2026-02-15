#!/bin/bash
# telos PreCompact hook — saves session context before compaction
# Extracts key decisions and progress from transcript, appends to daily note
# Ensures important context survives context window compression

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

# Extract transcript path and compaction trigger
TRANSCRIPT_PATH=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    print(data.get('transcript_path', ''))
except:
    pass
" "$INPUT" 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Extract a compact summary of recent work from the transcript
SUMMARY=$(python3 << 'PYEOF' "$TRANSCRIPT_PATH"
import sys, json

transcript_path = sys.argv[1]
try:
    messages = []
    with open(transcript_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
                messages.append(msg)
            except:
                continue

    if not messages:
        sys.exit(0)

    # Collect recent assistant messages (last 20) for key info
    assistant_texts = []
    for msg in messages[-40:]:
        role = msg.get('role', '')
        if role == 'assistant':
            content = msg.get('content', '')
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text = block.get('text', '')
                        if len(text) > 20:
                            assistant_texts.append(text[:300])
            elif isinstance(content, str) and len(content) > 20:
                assistant_texts.append(content[:300])

    if not assistant_texts:
        sys.exit(0)

    # Take last few meaningful messages as context snapshot
    recent = assistant_texts[-5:]
    summary_parts = []
    for t in recent:
        first_line = t.split('\n')[0].strip()
        if first_line:
            summary_parts.append(first_line)

    if summary_parts:
        print(' -> '.join(summary_parts[-3:]))

except Exception:
    pass
PYEOF
)

if [ -z "$SUMMARY" ]; then
  exit 0
fi

TIMESTAMP=$(date +%H:%M)
ENTRY="- ${TIMESTAMP} [pre-compact] Context about to be compressed. Recent work: ${SUMMARY}"

vault_daily_append "$ENTRY"

exit 0
