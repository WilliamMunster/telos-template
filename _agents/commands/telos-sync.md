Check TELOS cross-file status consistency and suggest sync actions when inconsistencies are found.

When the user invokes /telos-sync, do the following:

## Step 1: Load all TELOS status files

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

echo "===GOALS==="
obsidian read file=goals 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===PROJECTS==="
obsidian read file=projects 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===WORKLOG==="
obsidian read file=worklog 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===CHALLENGES==="
obsidian read file=challenges 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===IDENTITY==="
obsidian read file=identity 2>&1 &
PID=$!; sleep 5; kill $PID 2>/dev/null; wait $PID 2>/dev/null

# macOS-only
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 2: Cross-check consistency

Compare across files, look for:

1. **goals <-> projects**: Is project status consistent with OKR progress?
2. **goals <-> worklog**: Are completed KRs reflected in worklog completed list? Do pending work items correspond to incomplete KRs?
3. **worklog <-> challenges**: Do active work items have corresponding challenges? Are resolved challenges still in the active list?
4. **identity <-> goals**: Is identity positioning consistent with current goal phase?
5. **Date consistency**: Do `updated` fields in each file reflect recent modifications?

## Step 3: Report findings

Output a structured report:

### TELOS Consistency Check

**Consistent**
- ...

**Inconsistent**
- goals X marked done, but projects still shows in-progress -> suggest updating projects
- worklog has pending item Y, but goals shows it complete -> suggest moving to completed
- ...

## Step 4: Apply fixes

If inconsistencies found, ask: Apply automatic fixes?

If yes, use Edit tool to update the relevant files, then commit:

```bash
cd "$(git rev-parse --show-toplevel)"
git add _telos/
git commit -m "sync: telos consistency update via /telos-sync"
```

## Notes

- This is a read-heavy, write-light operation — most of the time just reports
- Run it after major status changes or as part of weekly review
- Does NOT create new content, only aligns existing status across files
