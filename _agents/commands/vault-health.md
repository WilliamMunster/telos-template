Check Obsidian vault health, reporting orphan notes, dead ends, unresolved links, and tag distribution.

When the user invokes /vault-health, do the following:

## Step 1: Collect vault health data

Run all checks in parallel:

```bash
# macOS-only: front app switching
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

echo "===ORPHANS==="
obsidian orphans 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===DEADENDS==="
obsidian deadends 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===UNRESOLVED==="
obsidian unresolved verbose 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===TAGS==="
obsidian tags all counts sort=count 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===FILES==="
obsidian files total 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===FOLDERS==="
obsidian folders total 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

# macOS-only
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 2: Generate health report

Produce a concise report with these sections:

1. **Overview** — total files, folders, tags count
2. **Orphans** — files with no incoming links. Exclude `_claude/`, `_templates/`, `_journal/daily/` (these are expected to have no backlinks). Flag others as needing attention.
3. **Dead ends** — files with no outgoing links. Exclude daily notes and templates. These may need wikilinks added.
4. **Unresolved links** — broken `[[links]]` that point to non-existent notes. These should be fixed or the target notes created.
5. **Tag distribution** — show tag usage. Flag any tags used only once (potential typos or inconsistency).

## Step 3: Suggest actions

Based on the findings, suggest specific actions:
- Which orphans should be linked from other notes
- Which unresolved links should be created as new notes
- Which tags might be typos or should be consolidated
- Any structural improvements

Keep suggestions actionable and brief. Do NOT auto-fix anything — present findings and let the user decide.

## Notes

- Obsidian must be running for CLI to work. If commands return no data, tell the user to open Obsidian first.
- Filter out CLI noise lines (Loading app package, Checking for update, etc.) from the output before analyzing.
