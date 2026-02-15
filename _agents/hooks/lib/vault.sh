#!/bin/bash
# vault.sh — Obsidian vault operations with fallback
# Source this file: source "$(dirname "$0")/vault.sh"

TELOS_VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"

# Platform-aware Obsidian path
if [[ "$OSTYPE" == darwin* ]]; then
  OBS="${OBS:-/Applications/Obsidian.app/Contents/MacOS/Obsidian}"
elif [[ "$OSTYPE" == linux* ]]; then
  # Check common Linux install locations
  if [ -x "/usr/bin/obsidian" ]; then
    OBS="${OBS:-/usr/bin/obsidian}"
  elif [ -x "/usr/local/bin/obsidian" ]; then
    OBS="${OBS:-/usr/local/bin/obsidian}"
  elif [ -x "$HOME/.local/bin/obsidian" ]; then
    OBS="${OBS:-$HOME/.local/bin/obsidian}"
  else
    OBS="${OBS:-obsidian}"
  fi
else
  OBS="${OBS:-obsidian}"
fi

# Portable sed -i wrapper
_sed_i() {
  if [[ "$OSTYPE" == darwin* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Check if Obsidian CLI is available and running
vault_available() {
  [ -x "$OBS" ] && pgrep -q "[Oo]bsidian"
}

# Poll-wait for a background process (max ~5s at 0.1s intervals)
_vault_poll_wait() {
  local pid=$1 max=${2:-50}
  local i=0
  while [ $i -lt $max ] && kill -0 "$pid" 2>/dev/null; do
    sleep 0.1; i=$((i + 1))
  done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}

# Append content to daily note under ## Log section
# Inserts between "## Log" and the next "## " header, not at EOF
# Usage: vault_daily_append "- 10:30 some entry"
vault_daily_append() {
  local content="$1"
  if [ ! -d "$TELOS_VAULT/_journal/daily" ]; then
    echo "[vault] No vault access" >&2
    return 1
  fi
  local today=$(date +%Y-%m-%d)
  local daily_file="$TELOS_VAULT/_journal/daily/${today}.md"
  if [ ! -f "$daily_file" ]; then
    echo "[vault] Daily note $daily_file not found, skipping" >&2
    return 1
  fi
  # Find ## Log line
  local log_line=$(grep -n '^## Log' "$daily_file" | head -1 | cut -d: -f1)
  if [ -z "$log_line" ]; then
    # No ## Log section, append to EOF as fallback
    echo "$content" >> "$daily_file"
    return 0
  fi
  # Find next ## header after ## Log
  local next_section=$(tail -n +"$((log_line + 1))" "$daily_file" | grep -n '^## ' | head -1 | cut -d: -f1)
  if [ -n "$next_section" ]; then
    local insert_line=$((log_line + next_section))
    local prev_line=$((insert_line - 1))
    local prev_content
    prev_content=$(sed -n "${prev_line}p" "$daily_file")
    if [ -z "$prev_content" ]; then
      # Blank line before next section — insert before it to keep spacing
      _sed_i "${prev_line}i\\
${content}" "$daily_file"
    else
      # No blank line — insert with trailing blank line
      _sed_i "${insert_line}i\\
${content}\\
" "$daily_file"
    fi
  else
    # No next section after ## Log, append to EOF
    echo "$content" >> "$daily_file"
  fi
}

# Read a vault note
# Usage: vault_read "goals"
vault_read() {
  local file="$1"

  # Special case: daily note
  if [ "$file" = "daily" ]; then
    local today=$(date +%Y-%m-%d)
    local daily_file="$TELOS_VAULT/_journal/daily/${today}.md"
    if [ -f "$daily_file" ]; then
      cat "$daily_file"
      return 0
    else
      echo "[vault] Daily note for $today not found" >&2
      return 1
    fi
  fi

  if vault_available; then
    local tmpfile=$(mktemp)
    $OBS read file="$file" 2>&1 > "$tmpfile" &
    _vault_poll_wait $!
    cat "$tmpfile"
    rm "$tmpfile"
  elif [ -d "$TELOS_VAULT" ]; then
    local found
    found=$(find "$TELOS_VAULT" -name "${file}.md" -not -path "*/\.*" -print -quit 2>/dev/null)
    if [ -n "$found" ]; then
      cat "$found"
    else
      echo "[vault] File $file not found" >&2
    fi
  fi
}

# Search vault
# Usage: vault_search "keyword" 3
vault_search() {
  local query="$1" limit="${2:-3}"
  if vault_available; then
    $OBS search query="$query" limit="$limit" matches 2>&1 &
    _vault_poll_wait $! 30
  fi
}

# Filter Obsidian CLI noise from output
vault_filter_noise() {
  grep -v "^20[0-9][0-9]-" | grep -v "Loading updated" | \
  grep -v "Checking for update" | grep -v "^Success\." | \
  grep -v "Latest version" | grep -v "App is up to date" | \
  sed '/^---$/,/^---$/d'
}
