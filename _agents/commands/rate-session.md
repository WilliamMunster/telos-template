Rate the current session quality and record it to the daily log for pattern analysis.

When the user invokes /rate-session, do the following:

## Step 1: Ask for rating

If the user provided a rating after the command (e.g., `/rate-session 4 smooth session`), use that directly.

Otherwise, ask:

Rate this session (1-5):
- 5 = Perfect, exceeded expectations
- 4 = Smooth, goals achieved
- 3 = Average, some friction
- 2 = Not great, multiple reworks
- 1 = Poor, goals not met

You can add a short comment.

## Step 2: Record the rating

```bash
source "$HOME/.agents/hooks/lib/vault.sh"
TIMESTAMP=$(date +%H:%M)
# RATING and COMMENT should be extracted from user input
vault_daily_append "- ${TIMESTAMP} [session-rating] ${RATING}/5 ${COMMENT}"
```

## Step 3: If rating <= 2, capture lesson

If the rating is 2 or below, ask: What was the main blocker?

Then append the friction point to `_telos/lessons.md`:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
obsidian read file=lessons 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

Read the current lessons, then append the new lesson using Edit tool on `_telos/lessons.md`.

## Step 4: Confirm

Reply: Recorded. Brief summary of rating and notes.

## Notes

- Keep it lightweight — one command, done
- Low ratings automatically trigger lesson capture
- Data accumulates in daily notes for weekly-review to analyze
