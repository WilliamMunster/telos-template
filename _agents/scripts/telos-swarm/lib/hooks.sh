#!/bin/bash
# hooks.sh — Swarm lifecycle hooks engine
# Source this file from telos-swarm.sh
#
# Event contract:
#   Events: swarm_start | swarm_stop | task_complete | arena_complete
#   Payload: env vars (SWARM_EVENT, SWARM_SESSION, SWARM_SESSION_DIR, SWARM_TIMESTAMP, ...)
#   Failure: non-blocking, warning to stderr
#   Idempotency: consumers must be reentrant

# Fire a hook event
# Usage: hooks_fire "event_name" [extra_env_pairs...]
# Extra env pairs: "KEY=value" "KEY2=value2"
hooks_fire() {
  local event="$1"
  shift

  local session="${SWARM_SESSION:-}"
  local session_dir="${SWARM_SESSION_DIR:-}"
  local timestamp
  timestamp=$(date +%s)

  # Build environment for hook scripts
  local hook_env=(
    "SWARM_EVENT=$event"
    "SWARM_SESSION=$session"
    "SWARM_SESSION_DIR=$session_dir"
    "SWARM_TIMESTAMP=$timestamp"
  )

  # Append extra env pairs
  for pair in "$@"; do
    hook_env+=("$pair")
  done

  # Collect hook scripts in discovery order
  local scripts=()
  shopt -s nullglob

  # 1. Session-level hooks
  if [ -n "$session_dir" ] && [ -d "$session_dir/.swarm/hooks/$event" ]; then
    for f in "$session_dir/.swarm/hooks/$event"/*.sh; do
      [ -f "$f" ] && [ -x "$f" ] && scripts+=("$f")
    done
  fi

  # 2. Global hooks
  local global_hooks="$HOME/.telos-swarm/hooks/$event"
  if [ -d "$global_hooks" ]; then
    for f in "$global_hooks"/*.sh; do
      [ -f "$f" ] && [ -x "$f" ] && scripts+=("$f")
    done
  fi

  shopt -u nullglob

  # 3. Builtin hooks
  local builtin_hook="$SCRIPT_DIR/hooks/builtin/${event}.sh"
  if [ -f "$builtin_hook" ] && [ -x "$builtin_hook" ]; then
    scripts+=("$builtin_hook")
  fi

  # Nothing to run
  [ ${#scripts[@]} -eq 0 ] && return 0

  # Execute each hook script with the environment
  # Avoid pipeline to ensure non-blocking semantics under set -euo pipefail
  for script in "${scripts[@]}"; do
    local exit_code=0
    local output
    output=$( (
      for pair in "${hook_env[@]}"; do
        export "${pair?}"
      done
      "$script"
    ) 2>&1 ) || exit_code=$?

    # Relay output with [hooks] prefix
    if [ -n "$output" ]; then
      while IFS= read -r line; do
        echo "[hooks] $line"
      done <<< "$output"
    fi

    if [ "$exit_code" -ne 0 ]; then
      echo "[hooks] warning: $event hook $(basename "$script") failed (exit $exit_code)" >&2
    fi
  done
}
