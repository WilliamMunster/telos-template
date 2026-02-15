#!/bin/bash
# session-logger.sh — Shared session logging logic
# Called by CLI-specific adapters with normalized arguments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/vault.sh"

# Log session start context
# Usage: session_log_start
# Reads daily note, projects, goals, lessons, worklog and outputs assembled context
session_log_start() {
  if ! vault_available; then
    echo "[telos] Obsidian is not running. Start Obsidian for full context loading."
    return 1
  fi

  local TMPDIR_HOOK=$(mktemp -d)

  # Sequential reads (vault_read already has internal timeout + cleanup)
  vault_read "daily"    | vault_filter_noise > "$TMPDIR_HOOK/daily" 2>/dev/null
  vault_read "projects" | vault_filter_noise > "$TMPDIR_HOOK/projects" 2>/dev/null
  vault_read "lessons"  | vault_filter_noise > "$TMPDIR_HOOK/lessons" 2>/dev/null
  vault_read "goals"    | vault_filter_noise > "$TMPDIR_HOOK/goals" 2>/dev/null
  vault_read "worklog"  | vault_filter_noise > "$TMPDIR_HOOK/worklog" 2>/dev/null

  local CONTEXT="[telos context loaded]"
  for pair in "daily:Today's Daily Note" "projects:Active Projects" \
              "lessons:Recent Lessons" "goals:Current Goals" "worklog:Active Worklog"; do
    local key="${pair%%:*}"
    local heading="${pair#*:}"
    local content=$(cat "$TMPDIR_HOOK/$key" 2>/dev/null)
    if [ -n "$content" ]; then
      CONTEXT="$CONTEXT\n\n## $heading\n$content"
    fi
  done

  rm -rf "$TMPDIR_HOOK"
  echo -e "$CONTEXT"
}

# Log session end
# Usage: session_log_end "summary text"
session_log_end() {
  local summary="$1"
  if [ -n "$summary" ]; then
    local timestamp=$(date +%H:%M)
    vault_daily_append "- ${timestamp} [session-end] ${summary}"
  fi
}

# Check telos cross-file consistency
# Only runs if today's daily note has _telos/ file edits
# Appends warning to daily note if inconsistencies found; silent otherwise
# Usage: session_check_telos_consistency
session_check_telos_consistency() {
  local today
  today=$(date +%Y-%m-%d)
  local daily_file="$TELOS_VAULT/_journal/daily/${today}.md"
  [ -f "$daily_file" ] || return 0

  # Check if any _telos/ files were edited/created today
  if ! grep -q '\[file-\(edited\|created\)\] _telos/' "$daily_file"; then
    return 0
  fi

  local goals_file="$TELOS_VAULT/_telos/goals.md"
  local worklog_file="$TELOS_VAULT/_telos/worklog.md"
  local projects_file="$TELOS_VAULT/_telos/projects.md"
  local issues=0

  local check_result
  check_result=$(
    (
      sleep 2 && kill $$ 2>/dev/null
    ) &
    local timer_pid=$!

    local msgs=""

    # Check: goals with completed markers — corresponding worklog items should be done
    if [ -f "$goals_file" ] && [ -f "$worklog_file" ]; then
      local done_objectives
      done_objectives=$(grep -E '^### .*✅' "$goals_file" | sed 's/^### \([A-Za-z0-9]*\).*/\1/')

      local wl_active_objectives
      wl_active_objectives=$(sed -n '/^## .*[Aa]ctive\|^## .*进行中/,/^## /p' "$worklog_file" | grep '|' | grep -v '---' | sed 's/.*| *\([A-Za-z0-9]*\) *.*/\1/' | sort -u)

      for obj in $done_objectives; do
        if echo "$wl_active_objectives" | grep -q "^${obj}$"; then
          msgs="${msgs}goals ${obj} marked done but worklog still has active items; "
        fi
      done
    fi

    kill "$timer_pid" 2>/dev/null
    wait "$timer_pid" 2>/dev/null

    echo "$msgs"
  ) 2>/dev/null

  if [ -n "$check_result" ]; then
    issues=$(echo "$check_result" | tr ';' '\n' | grep -c '[a-zA-Z]')
  fi

  if [ "$issues" -gt 0 ]; then
    local timestamp
    timestamp=$(date +%H:%M)
    vault_daily_append "- ${timestamp} [telos-check] Found ${issues} inconsistencies, consider running /telos-sync: ${check_result}"
  fi
}
