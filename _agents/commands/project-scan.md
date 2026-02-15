Scan the local project directory, auto-discover projects, and update _telos/projects.md.

When the user invokes /project-scan, do the following:

## Step 1: Scan project directory

```bash
PROJECT_DIR="${TELOS_PROJECT_DIR:-$HOME/project}"
for dir in "$PROJECT_DIR"/*/; do
  [ -d "$dir" ] || continue
  NAME=$(basename "$dir")
  echo "=== $NAME ==="

  # Check git remote
  if [ -d "$dir/.git" ]; then
    REMOTE=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "local only")
    BRANCH=$(git -C "$dir" branch --show-current 2>/dev/null || echo "unknown")
    LAST_COMMIT=$(git -C "$dir" log -1 --format="%ai %s" 2>/dev/null || echo "no commits")
    echo "remote: $REMOTE"
    echo "branch: $BRANCH"
    echo "last_commit: $LAST_COMMIT"
  else
    echo "not a git repo"
  fi

  # Detect tech stack
  [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ] && echo "stack: python"
  [ -f "$dir/package.json" ] && echo "stack: node"
  [ -f "$dir/pom.xml" ] && echo "stack: java/maven"
  [ -f "$dir/build.gradle" ] && echo "stack: java/gradle"
  [ -f "$dir/Cargo.toml" ] && echo "stack: rust"
  [ -f "$dir/go.mod" ] && echo "stack: go"

  echo ""
done
```

## Step 2: Determine device context

Check hostname to determine device type:
```bash
hostname
```

Tag projects accordingly:
- Personal machine -> projects are likely personal
- Company machine -> projects are likely company or company-derived

Ask the user to confirm the classification if unsure.

## Step 3: Read current projects.md

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
obsidian read file=projects 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 4: Show diff and update

Compare scanned results with current projects.md:
- New projects found -> suggest adding
- Existing projects -> update last commit, status
- Missing projects (deleted locally) -> flag for review

After confirmation, update projects.md directly.

## Notes

- Do NOT auto-remove projects from projects.md — they might exist on another device.
- Mark device-specific info (e.g., `[personal-mac]`, `[company-mac]`) so multi-device projects are clear.
- Keep the table format consistent with existing projects.md structure.
- If a project has no git remote, suggest the user initialize one.
