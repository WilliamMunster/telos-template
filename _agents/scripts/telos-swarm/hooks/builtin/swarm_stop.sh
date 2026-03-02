#!/bin/bash
# builtin hook: swarm_stop — append session summary to daily note
# Idempotency: checks for existing entry with same session name + timestamp prefix

VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
TODAY=$(date +%Y-%m-%d)
DAILY="$VAULT/_journal/daily/${TODAY}.md"
TIMESTAMP=$(date +%H:%M)

[ -f "$DAILY" ] || exit 0
[ -n "$SWARM_SESSION_DIR" ] || exit 0

# Gather stats from task files
total=0 done_count=0 failed=0 quality_pass=0
shopt -s nullglob
for f in "$SWARM_SESSION_DIR/.swarm/tasks"/*.env; do
  [ -f "$f" ] || continue
  total=$((total + 1))
  status=$(grep '^STATUS=' "$f" | cut -d'"' -f2)
  quality=$(grep '^QUALITY=' "$f" | cut -d'"' -f2)
  case "$status" in
    done) done_count=$((done_count + 1)) ;;
    failed) failed=$((failed + 1)) ;;
  esac
  [ "$quality" = "pass" ] && quality_pass=$((quality_pass + 1))
done
shopt -u nullglob

[ "$total" -eq 0 ] && exit 0

# Calculate quality rate
quality_pct=0
[ "$done_count" -gt 0 ] && quality_pct=$((quality_pass * 100 / done_count))

# Idempotency: include timestamp to distinguish re-runs of same session name
entry_marker="[swarm] ${SWARM_SESSION}/${SWARM_TIMESTAMP}:"
if grep -qF "$entry_marker" "$DAILY" 2>/dev/null; then
  exit 0
fi

# Append to daily note
summary="- ${TIMESTAMP} ${entry_marker} ${total} tasks, ${done_count} done, ${failed} failed, quality ${quality_pct}%"

# Use Obsidian CLI if available, otherwise direct append
OBS="/Applications/Obsidian.app/Contents/MacOS/Obsidian"
if [ -x "$OBS" ] && pgrep -q Obsidian; then
  "$OBS" "daily:append" "content=${summary}" 2>/dev/null || echo "$summary" >> "$DAILY"
else
  echo "$summary" >> "$DAILY"
fi
