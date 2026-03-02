#!/bin/bash
# cli.sh — CLI detection, capabilities, and launch commands
# Source this file from telos-swarm.sh

# Detect available AI CLIs on current device
# Returns space-separated list
cli_detect() {
  local available=""
  for cli in claude gemini codex kimi; do
    if command -v "$cli" &>/dev/null; then
      available="${available:+$available }$cli"
    fi
  done
  echo "$available"
}

# CLI capability descriptions (for TL analysis)
cli_capabilities() {
  local cli="$1"
  case "$cli" in
    claude)
      echo "最强综合能力，支持 team 功能，适合架构设计、复杂编码、代码审查、TL 角色。可 spawn 子 agent 并行工作。"
      ;;
    gemini)
      echo "大上下文窗口（1M tokens），适合调研、文档分析、长文本处理、代码理解。"
      ;;
    codex)
      echo "代码生成强，沙盒执行，适合编码、重构、批量修改、自动化脚本。"
      ;;
    kimi)
      echo "中文理解强，长上下文，适合中文内容创作、翻译、头脑风暴、文档撰写。"
      ;;
    *)
      echo "未知 CLI: $cli" >&2
      return 1
      ;;
  esac
}

# Interactive mode launch command
cli_interactive_cmd() {
  local cli="$1"
  case "$cli" in
    claude) echo "claude" ;;
    gemini) echo "gemini" ;;
    codex)  echo "codex" ;;
    kimi)   echo "kimi" ;;
    *)
      echo "未知 CLI: $cli" >&2
      return 1
      ;;
  esac
}

# Non-interactive command with prompt (for TL analysis)
cli_headless_cmd() {
  local cli="$1" prompt="$2"
  case "$cli" in
    claude) echo "claude -p $(printf '%q' "$prompt")" ;;
    gemini) echo "gemini -p $(printf '%q' "$prompt")" ;;
    codex)  echo "codex -q $(printf '%q' "$prompt")" ;;
    kimi)   echo "kimi -p $(printf '%q' "$prompt")" ;;
    *)
      echo "未知 CLI: $cli" >&2
      return 1
      ;;
  esac
}

# TL priority ordering — returns best available CLI for TL role
cli_tl_select() {
  local available="$1"
  for cli in claude kimi gemini codex; do
    if echo "$available" | grep -qw "$cli"; then
      echo "$cli"
      return 0
    fi
  done
  echo "无可用 CLI" >&2
  return 1
}

# Launch CLI in a tmux pane (handles env setup per CLI)
# Usage: cli_pane_launch <cli> <pane> [auto_approve]
# auto_approve: if "true", launch with permission-bypass flags for automation
cli_pane_launch() {
  local cli="$1" pane="$2" auto_approve="${3:-false}"
  case "$cli" in
    claude)
      # Unset nested session detection to allow running inside tmux
      if [ "$auto_approve" = "true" ]; then
        tmux send-keys -t "$pane" -- "unset CLAUDECODE && claude --dangerously-skip-permissions" Enter
      else
        tmux send-keys -t "$pane" -- "unset CLAUDECODE && claude" Enter
      fi
      ;;
    gemini)
      if [ "$auto_approve" = "true" ]; then
        tmux send-keys -t "$pane" -- "gemini --yolo" Enter
      else
        tmux send-keys -t "$pane" -- "gemini" Enter
      fi
      ;;
    codex)
      if [ "$auto_approve" = "true" ]; then
        tmux send-keys -t "$pane" -- "codex -a never" Enter
      else
        tmux send-keys -t "$pane" -- "codex" Enter
      fi
      ;;
    kimi)
      # Note: --agent-file requires YAML agent spec format, not plain Markdown.
      # Kimi reads its system prompt from ~/.kimi/ config instead.
      if [ "$auto_approve" = "true" ]; then
        tmux send-keys -t "$pane" -- "kimi --yolo" Enter
      else
        tmux send-keys -t "$pane" -- "kimi" Enter
      fi
      ;;
    *)
      echo "未知 CLI: $cli" >&2
      return 1
      ;;
  esac
}

# Wait for CLI to be ready to accept input
# Polls tmux pane content for CLI-specific ready indicators
# Usage: cli_wait_ready <cli> <pane> [timeout_seconds]
cli_wait_ready() {
  local cli="$1" pane="$2"
  # Default timeout varies by CLI — Codex is slow to start
  local default_timeout=15
  [ "$cli" = "codex" ] && default_timeout=30
  [ "$cli" = "claude" ] && default_timeout=30
  local timeout="${3:-$default_timeout}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    local content
    content=$(tmux capture-pane -t "$pane" -p 2>/dev/null || true)

    case "$cli" in
      gemini)
        # Gemini shows "Type your message" when ready
        if echo "$content" | grep -q "Type your message"; then
          sleep 1  # extra buffer for rendering
          return 0
        fi
        ;;
      claude)
        # Auto-accept --dangerously-skip-permissions confirmation prompt
        # Claude uses arrow-key navigation; "Down" selects option 2 "Yes, I accept"
        if echo "$content" | grep -qE "(Yes, I accept|Enter to confirm)"; then
          tmux send-keys -t "$pane" Down Enter
          sleep 3
          elapsed=$((elapsed + 3))
          continue
        fi
        # Claude shows ">" or "❯" prompt, Tips, or help text when ready
        if echo "$content" | grep -qE "(^>|^❯|Tips:|What can I)"; then
          sleep 1
          return 0
        fi
        ;;
      kimi)
        # Kimi shows welcome banner or status bar with "yolo" when ready
        if echo "$content" | grep -qE "(Welcome to Kimi|yolo)"; then
          sleep 1
          return 0
        fi
        ;;
      codex)
        # Codex shows "OpenAI Codex" banner or "context left" in status bar
        if echo "$content" | grep -qE "(OpenAI Codex|context left)"; then
          sleep 1
          return 0
        fi
        ;;
    esac

    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Timeout — send anyway, CLI might still be loading
  echo "[warn] $cli did not show ready indicator within ${timeout}s, sending task anyway" >&2
}

# Send task text to a CLI pane using tmux paste-buffer
# This avoids the narrow-pane truncation issue with send-keys
# Usage: cli_send_task <pane> <task_text>
cli_send_task() {
  local pane="$1" task="$2"
  local tmpfile
  tmpfile=$(mktemp /tmp/swarm-task-XXXXXX.txt)
  # Write task as single block (no trailing newline — Enter sent separately)
  printf '%s' "$task" > "$tmpfile"
  tmux load-buffer "$tmpfile"
  tmux paste-buffer -t "$pane" -d  # -d deletes buffer after paste
  sleep 0.5  # let TUI process paste event before sending Enter
  tmux send-keys -t "$pane" Enter
  rm -f "$tmpfile"
}

# Verify that a task was actually submitted (not stuck in input box)
# Retries Enter if the CLI hasn't started processing
# Usage: cli_verify_submitted <cli> <pane> <task_text>
cli_verify_submitted() {
  local cli="$1" pane="$2" task="$3"
  local max_retries=3 attempt=0

  while [ "$attempt" -lt "$max_retries" ]; do
    sleep 1
    local content
    content=$(tmux capture-pane -t "$pane" -p 2>/dev/null || true)

    case "$cli" in
      gemini)
        # Success: processing indicator or task text no longer in input line
        if echo "$content" | grep -qE "(Interpreting|Generating|Thinking|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏)"; then
          return 0
        fi
        ;;
      *)
        # Other CLIs: no verification needed yet
        return 0
        ;;
    esac

    # Text still in input box → retry Enter
    echo "[warn] $cli: task not submitted, retrying Enter (attempt $((attempt + 1)))" >&2
    tmux send-keys -t "$pane" Enter
    attempt=$((attempt + 1))
  done

  echo "[warn] $cli: task may not have been submitted after $max_retries retries" >&2
}

cli_format_available() {
  local available="$1"
  for cli in $available; do
    local cap
    cap=$(cli_capabilities "$cli")
    echo "- **$cli**: $cap"
  done
}
