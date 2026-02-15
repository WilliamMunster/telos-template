Summarize git commit history across all projects, generating a work summary. Supports daily/weekly views.

When the user invokes /work-summary, do the following:

## Step 1: Determine time range

If the user specified a range (e.g., `/work-summary today`, `/work-summary week`), use that.
Default: today.

- today: `--since="today 00:00"`
- week: `--since="7 days ago"`
- yesterday: `--since="yesterday 00:00" --until="today 00:00"`

## Step 2: Read project paths

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
obsidian read file=projects 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

From the projects.md, extract all local paths listed in the project paths table.

## Step 3: Collect git logs

For each project path that exists on this machine, run:

```bash
cd <project_path> && git log --oneline --since="<range>" --author="$(git config user.name)" --no-merges 2>/dev/null
```

Skip paths that don't exist (different device).

## Step 4: Format output

### Work Summary (<date range>)

**project-a** (N commits)
- abc1234 feat: add SessionEnd hook
- def5678 docs: update README

**project-b** (N commits)
- ...

**Total**: X projects, Y commits

If no commits found, say: No commits found for this time range.

## Step 5: Optionally log to daily note

Ask: Record to today's daily note?

If yes:
```bash
VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
TODAY=$(date +%Y-%m-%d)
DAILY="$VAULT/_journal/daily/${TODAY}.md"
echo "## Work Summary" >> "$DAILY"
echo "${SUMMARY}" >> "$DAILY"
```

## Notes

- Only shows commits from the current user (git config user.name)
- Skips merge commits for cleaner output
- Works across devices — only scans paths that exist locally
- Pairs well with /weekly-review for comprehensive weekly reports
