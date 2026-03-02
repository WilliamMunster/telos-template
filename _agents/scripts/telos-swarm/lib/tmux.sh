#!/bin/bash
# tmux.sh — tmux session/pane management and layout
# Source this file from telos-swarm.sh

# Create a new tmux session (detached)
tmux_create_session() {
  local session="$1" workdir="${2:-$HOME}"
  tmux new-session -d -s "$session" -c "$workdir" 2>&1
}

# Add a pane to an existing session
# Returns: pane id
tmux_add_pane() {
  local session="$1" title="$2" cmd="$3" workdir="${4:-$HOME}"

  # Split the current window horizontally (new pane below)
  local pane_id
  pane_id=$(tmux split-window -t "$session" -c "$workdir" -P -F '#{pane_id}' 2>&1)
  if [ $? -ne 0 ]; then
    echo "[tmux] Failed to add pane: $pane_id" >&2
    return 1
  fi

  # Set pane title
  tmux select-pane -t "$pane_id" -T "$title" 2>/dev/null

  # Send command to the pane
  if [ -n "$cmd" ]; then
    tmux send-keys -t "$pane_id" -- "$cmd" Enter
  fi

  echo "$pane_id"
}

# Send command to the first pane of a session (TL pane)
tmux_send_to_first() {
  local session="$1" cmd="$2"
  tmux send-keys -t "${session}:0.0" -- "$cmd" Enter
}

# Apply layout to session
tmux_layout() {
  local session="$1" count="$2" style="${3:-auto}"

  case "$style" in
    stack)
      tmux select-layout -t "$session" even-vertical
      ;;
    grid)
      tmux select-layout -t "$session" tiled
      ;;
    auto)
      case "$count" in
        1) ;; # single pane, no layout needed
        2) tmux select-layout -t "$session" even-horizontal ;;
        3) tmux select-layout -t "$session" even-horizontal ;;
        *) tmux select-layout -t "$session" tiled ;;
      esac
      ;;
    *)
      echo "[tmux] Unknown layout style: $style" >&2
      return 1
      ;;
  esac
}

# Attach to session (iTerm2 native mode if available, otherwise standard)
tmux_attach() {
  local session="$1"
  if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    exec tmux -CC attach-session -t "$session"
  else
    exec tmux attach-session -t "$session"
  fi
}

# Check if a tmux session exists
tmux_session_exists() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null
}

# Kill a tmux session
tmux_kill_session() {
  local session="$1"
  tmux kill-session -t "$session" 2>/dev/null
}

# Get pane count in a session
tmux_pane_count() {
  local session="$1"
  tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' '
}
