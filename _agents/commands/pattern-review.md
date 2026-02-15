Analyze recent logs and rating data, extract cross-session patterns, and generate an insights report.

When the user invokes /pattern-review, do the following:

## Step 1: Gather data

Read the last 7 days of daily notes:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

# Read recent daily notes (last 7 days)
for i in $(seq 0 6); do
  DATE=$(date -v-${i}d +%Y-%m-%d)
  echo "=== $DATE ==="
  obsidian read file="$DATE" 2>&1 &
  PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null
done

osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

Also read lessons and worklog:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

echo "=== LESSONS ==="
obsidian read file=lessons 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "=== WORKLOG ==="
obsidian read file=worklog 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 2: Analyze patterns

From the collected data, identify:

1. **Time patterns** — What time periods are most productive? When do you get stuck?
2. **Task patterns** — Which task types complete quickly? Which ones require rework?
3. **Tool patterns** — Which skills/hooks are used frequently? Which are unused?
4. **Mood patterns** — Session-rating trends, what scenarios correlate with low scores?
5. **Progress patterns** — OKR advancement speed, which goals are stalled?

## Step 3: Generate insights

Output a structured report:

### Weekly Pattern Analysis

**High-frequency activities**
- ...

**Efficiency insights**
- ...

**Risk signals**
- ...

**Suggested adjustments**
- ...

## Step 4: Optionally save

Ask: Save this analysis to today's daily note?

If yes:
```bash
VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
TODAY=$(date +%Y-%m-%d)
DAILY="$VAULT/_journal/daily/${TODAY}.md"
echo "## Pattern Analysis" >> "$DAILY"
echo "${ANALYSIS}" >> "$DAILY"
```

## Notes

- This skill is most useful when run weekly, after accumulating enough data
- Early on (first 1-2 weeks), patterns may be sparse — that's normal
- Focus on actionable insights, not just statistics
- Cross-reference with goals.md to check alignment
