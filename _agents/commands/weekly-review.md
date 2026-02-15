Perform a weekly review by reading this week's daily notes, summarizing key activities, extracting lessons, and updating telos documents.

When the user invokes /weekly-review, do the following:

## Step 1: Read this week's daily notes

Use Obsidian CLI to read each day's note. Calculate the date range (Monday to today):

```bash
# macOS-only: front app switching
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

# Read each day (skip if not found)
for i in $(seq 0 6); do
  DATE=$(date -v-${i}d +%Y-%m-%d)
  echo "=== $DATE ==="
  obsidian read file="$DATE" 2>&1 &
  PID=$!; sleep 4; kill $PID 2>/dev/null; wait $PID 2>/dev/null
done

# macOS-only
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 2: Collect git commits from all projects

Read `_telos/projects.md` to get project paths, then collect this week's commits:

```bash
# For each project path that exists locally:
cd <project_path> && git log --oneline --since="7 days ago" --author="$(git config user.name)" --no-merges 2>/dev/null
```

Skip paths that don't exist on this device.

## Step 3: Summarize

Based on all daily notes found and git commit history, produce a summary with these sections:

1. **Completed** — bullet list of what was accomplished (from daily notes + commits)
2. **Code output** — commits per project, key changes
3. **In progress** — what's still in progress
4. **Lessons learned** — problems encountered and what was learned
5. **Next week plan** — suggested focus for next week based on `_telos/goals.md`

## Step 4: Write weekly review

Create the weekly review note:

```bash
VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
MONDAY=$(date -v-monday +%Y-%m-%d)
mkdir -p "$VAULT/_journal/weekly"
cat > "$VAULT/_journal/weekly/${MONDAY}.md" << 'EOF'
<generated summary>
EOF
```

Use this frontmatter:
```yaml
---
tags:
  - journal
  - weekly
week: YYYY-WXX
date_range: YYYY-MM-DD ~ YYYY-MM-DD
---
```

## Step 5: Update lessons

If there are new lessons learned, append them to `_telos/lessons.md`.

## Step 6: Update project status

Read `_telos/goals.md` and suggest any OKR status updates based on what was accomplished this week. Show the suggested changes and ask the user to confirm before writing.

## Step 7: Archive maintenance

Check telos files for items that need archiving, show suggestions, execute after user confirmation.

### 7.1 Worklog completed items archive

Read `_telos/worklog.md` completed table, find entries completed more than 2 weeks ago. If any:
- Move these entries from completed table into a `<details>` collapsed section at the bottom
- Show the list and wait for user confirmation

### 7.2 Challenges resolved items archive

Read `_telos/challenges.md`, check for resolved items still in the active section. If any:
- Suggest moving them to the resolved section
- Show suggestions and wait for user confirmation

## Output

Show the weekly summary to the user. Confirm what was written and where. Keep it concise.
