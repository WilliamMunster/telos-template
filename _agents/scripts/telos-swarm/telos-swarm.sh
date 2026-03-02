#!/bin/bash
# telos-swarm — Multi-CLI AI agent orchestrator
# Version: 0.5.0
# Launches multiple AI CLIs in tmux panes for parallel work
#
# Usage:
#   telos-swarm start <config.yaml>
#   telos-swarm quick "task1" "task2" ...
#   telos-swarm add --<cli> "task"
#   telos-swarm status
#   telos-swarm merge [agent_id]
#   telos-swarm stop
#   telos-swarm clean

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || perl -e 'use Cwd "abs_path"; print abs_path(shift)' "$0")")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TMPL_DIR="$SCRIPT_DIR/templates"

# Source libraries
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/tmux.sh"
source "$LIB_DIR/worktree.sh"
source "$LIB_DIR/task.sh"
source "$LIB_DIR/hooks.sh"

# Directory layout
SWARM_HOME="$HOME/.telos-swarm"
SWARM_SESSIONS_DIR="$SWARM_HOME/sessions"
SWARM_STATE_FILE="$SWARM_HOME/current.env"

# ─── Dependency check ────────────────────────────────────────

check_deps() {
  local require_yq="${1:-false}"
  local missing=""
  for dep in tmux git; do
    if ! command -v "$dep" &>/dev/null; then
      missing="${missing:+$missing, }$dep"
    fi
  done

  if [ "$require_yq" = "true" ] && ! command -v yq &>/dev/null; then
    if command -v brew &>/dev/null; then
      read -p "yq 未安装（YAML 解析需要）。现在安装？[Y/n] " yn
      if [[ "${yn:-Y}" =~ ^[Yy]$ ]]; then
        brew install yq
      else
        missing="${missing:+$missing, }yq"
      fi
    else
      missing="${missing:+$missing, }yq (brew install yq)"
    fi
  fi

  if [ -n "$missing" ]; then
    echo "缺少依赖: $missing" >&2
    exit 1
  fi
}

# ─── State management ────────────────────────────────────────

state_save() {
  mkdir -p "$SWARM_HOME" "$SWARM_SESSIONS_DIR"
  local session_dir="$SWARM_SESSIONS_DIR/$1"
  mkdir -p "$session_dir/.swarm/tasks" "$session_dir/.swarm/prompts" "$session_dir/.swarm/outputs"
  local tl_cli="${7:-}"
  local tl_pane="${8:-}"
  # Quote all values to handle paths with spaces (e.g. "Obsidian Vault")
  cat > "$SWARM_STATE_FILE" <<EOF
SWARM_SESSION="$1"
SWARM_PROJECT="$2"
SWARM_WORKTREE="$3"
SWARM_BASE_BRANCH="$4"
SWARM_LAYOUT="$5"
SWARM_PANE_COUNT="$6"
SWARM_TL_CLI="$tl_cli"
SWARM_TL_PANE="$tl_pane"
SWARM_SESSION_DIR="$session_dir"
EOF
}

state_load() {
  if [ ! -f "$SWARM_STATE_FILE" ]; then
    echo "没有运行中的 swarm。" >&2
    return 1
  fi
  source "$SWARM_STATE_FILE"
}

state_update_pane_count() {
  if [ -f "$SWARM_STATE_FILE" ]; then
    local count
    count=$(tmux_pane_count "$SWARM_SESSION" 2>/dev/null || echo "0")
    sed -i '' "s/^SWARM_PANE_COUNT=.*/SWARM_PANE_COUNT=\"$count\"/" "$SWARM_STATE_FILE"
  fi
}

state_clear() {
  rm -f "$SWARM_STATE_FILE"
}

# ─── TL prompt generation ────────────────────────────────────

generate_tl_prompt() {
  local available_clis="$1" tasks="$2" context="$3"

  local cli_info
  cli_info=$(cli_format_available "$available_clis")

  local prompt
  prompt=$(cat "$TMPL_DIR/tl-prompt.md")
  prompt="${prompt//\{\{available_clis\}\}/$cli_info}"
  prompt="${prompt//\{\{tasks\}\}/$tasks}"
  prompt="${prompt//\{\{context\}\}/$context}"

  echo "$prompt"
}

# ─── Subcommands ──────────────────────────────────────────────

cmd_start() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    echo "配置文件不存在: $config_file" >&2
    exit 1
  fi

  check_deps true

  # Parse YAML
  local session project base_branch use_worktree tl_cli use_team context layout
  session=$(yq '.session // "swarm"' "$config_file")
  project=$(yq '.project // ""' "$config_file")
  project="${project/#\~/$HOME}"
  base_branch=$(yq '.base_branch // "main"' "$config_file")
  use_worktree=$(yq '.worktree // false' "$config_file")
  tl_cli=$(yq '.tl.cli // ""' "$config_file")
  use_team=$(yq '.tl.use_team // false' "$config_file")
  context=$(yq '.context // ""' "$config_file")
  layout=$(yq '.layout // "auto"' "$config_file")

  # Quality gate config (exported for task.sh)
  export SWARM_QUALITY_MIN_LINES
  SWARM_QUALITY_MIN_LINES=$(yq '.quality.min_lines // ""' "$config_file")
  export SWARM_QUALITY_ERROR_PATTERNS
  SWARM_QUALITY_ERROR_PATTERNS=$(yq '.quality.error_patterns // ""' "$config_file")

  # Detect available CLIs
  local available
  available=$(cli_detect)
  if [ -z "$available" ]; then
    echo "未检测到任何可用的 AI CLI。" >&2
    exit 1
  fi
  echo "可用 CLI: $available"

  # Select TL
  if [ -z "$tl_cli" ]; then
    tl_cli=$(cli_tl_select "$available")
  fi
  if ! echo "$available" | grep -qw "$tl_cli"; then
    echo "指定的 TL CLI ($tl_cli) 不可用。" >&2
    exit 1
  fi
  echo "TL: $tl_cli"

  # Parse tasks
  local task_count
  task_count=$(yq '.tasks | length' "$config_file")
  local tasks_text=""
  for i in $(seq 0 $((task_count - 1))); do
    local tid tdesc ttype
    tid=$(yq ".tasks[$i].id" "$config_file")
    tdesc=$(yq ".tasks[$i].description" "$config_file")
    ttype=$(yq ".tasks[$i].type // \"general\"" "$config_file")
    tasks_text="${tasks_text}- [$tid] ($ttype): $tdesc"$'\n'
  done

  # Check for manual assignments
  local has_assignments
  has_assignments=$(yq '.assignments // {} | length' "$config_file")

  # Kill existing session if present
  if tmux_session_exists "$session"; then
    echo "Session '$session' 已存在，将重建..."
    tmux_kill_session "$session"
  fi

  # Determine workdir
  local workdir="$HOME"
  if [ -n "$project" ] && [ -d "$project" ]; then
    workdir="$project"
  fi

  # Create tmux session
  tmux_create_session "$session" "$workdir"

  # Generate TL prompt
  local tl_prompt
  tl_prompt=$(generate_tl_prompt "$available" "$tasks_text" "$context")

  # Launch TL in first pane
  cli_pane_launch "$tl_cli" "${session}:0.0"

  # Wait briefly for CLI to start, then send the prompt
  sleep 2
  # Write prompt to a temp file and instruct TL to read it
  local prompt_file="$SWARM_HOME/tl-prompt-${session}.md"
  mkdir -p "$SWARM_HOME"
  echo "$tl_prompt" > "$prompt_file"
  tmux send-keys -t "${session}:0.0" -- "请阅读分析任务: $prompt_file" Enter

  # Set pane title
  tmux select-pane -t "${session}:0.0" -T "TL:${tl_cli}" 2>/dev/null

  # If manual assignments exist, create panes immediately
  if [ "$has_assignments" -gt 0 ]; then
    echo "检测到手动分配，创建 agent pane..."
    local pane_count=1
    for i in $(seq 0 $((task_count - 1))); do
      local tid tdesc
      tid=$(yq ".tasks[$i].id" "$config_file")
      tdesc=$(yq ".tasks[$i].description" "$config_file")
      local assigned_cli
      assigned_cli=$(yq ".assignments.${tid} // \"\"" "$config_file")
      if [ -n "$assigned_cli" ] && echo "$available" | grep -qw "$assigned_cli"; then
        local agent_workdir="$workdir"
        if [ "$use_worktree" = "true" ] && [ -n "$project" ]; then
          agent_workdir=$(worktree_create "$project" "$tid" "$base_branch") || agent_workdir="$workdir"
        fi
        tmux_add_pane "$session" "${tid}:${assigned_cli}" "" "$agent_workdir"
        pane_count=$((pane_count + 1))
        local last_pane
        last_pane=$(tmux list-panes -t "$session" -F '#{pane_id}' | tail -1)
        cli_pane_launch "$assigned_cli" "$last_pane"
        sleep 2
        # Send task description
        last_pane=$(tmux list-panes -t "$session" -F '#{pane_id}' | tail -1)
        cli_send_task "$last_pane" "$tdesc"
        cli_verify_submitted "$assigned_cli" "$last_pane" "$tdesc"
      fi
    done
    tmux_layout "$session" "$pane_count" "$layout"
  fi

  # Save state (including TL identity)
  local total_panes
  total_panes=$(tmux_pane_count "$session")
  local tl_pane_id
  tl_pane_id=$(tmux list-panes -t "${session}:0" -F '#{pane_id}' | head -1)
  state_save "$session" "$project" "$use_worktree" "$base_branch" "$layout" "$total_panes" "$tl_cli" "$tl_pane_id"

  # Auto-detect and register pane mappings
  local session_dir="$SWARM_SESSIONS_DIR/$session"
  pane_auto_detect "$session_dir" "$session"

  echo ""
  echo "Swarm '$session' 已启动。"
  echo "TL ($tl_cli) 正在分析任务分配..."
  echo ""
  echo "确认分配后，使用以下命令添加 agent:"
  echo "  telos-swarm add --<cli> \"任务描述\""
  echo ""

  hooks_fire "swarm_start"

  # Attach with iTerm2 native integration
  tmux_attach "$session"
}

cmd_quick() {
  local tl_cli="" project="" base_branch="main" use_worktree="true" layout="auto"
  local auto_approve="false"
  local tasks=()
  local manual_assignments=()

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --tl)
        tl_cli="$2"; shift 2 ;;
      --project)
        project="${2/#\~/$HOME}"; shift 2 ;;
      --base)
        base_branch="$2"; shift 2 ;;
      --no-worktree)
        use_worktree="false"; shift ;;
      --layout)
        layout="$2"; shift 2 ;;
      --auto-approve)
        auto_approve="true"; shift ;;
      --claude|--gemini|--codex|--kimi)
        local cli="${1#--}"
        manual_assignments+=("$cli:$2")
        tasks+=("$2")
        shift 2 ;;
      -*)
        echo "未知选项: $1" >&2; exit 1 ;;
      *)
        tasks+=("$1"); shift ;;
    esac
  done

  if [ ${#tasks[@]} -eq 0 ]; then
    echo "请至少提供一个任务。" >&2
    echo "用法: telos-swarm quick \"任务1\" \"任务2\" ..." >&2
    exit 1
  fi

  check_deps

  local available
  available=$(cli_detect)
  if [ -z "$available" ]; then
    echo "未检测到任何可用的 AI CLI。" >&2
    exit 1
  fi

  # Select TL
  if [ -z "$tl_cli" ]; then
    tl_cli=$(cli_tl_select "$available")
  fi

  local session="swarm-$(date +%H%M%S)"
  local workdir="$HOME"
  if [ -n "$project" ] && [ -d "$project" ]; then
    workdir="$project"
  fi

  # Kill existing session if present
  tmux_session_exists "$session" && tmux_kill_session "$session"

  # Create session
  tmux_create_session "$session" "$workdir"

  # If manual assignments, launch all panes directly
  if [ ${#manual_assignments[@]} -gt 0 ]; then
    # Phase 1: Create all panes first (before launching CLIs)
    local -a pane_ids=()
    local first_pane_id
    first_pane_id=$(tmux list-panes -t "${session}:0" -F '#{pane_id}' | head -1)
    pane_ids+=("$first_pane_id")
    tmux select-pane -t "$first_pane_id" -T "${manual_assignments[0]%%:*}" 2>/dev/null

    for i in $(seq 1 $((${#manual_assignments[@]} - 1))); do
      local entry="${manual_assignments[$i]}"
      local cli="${entry%%:*}"
      local agent_workdir="$workdir"
      if [ "$use_worktree" = "true" ] && [ -n "$project" ]; then
        agent_workdir=$(worktree_create "$project" "agent-$i" "$base_branch" 2>/dev/null) || agent_workdir="$workdir"
      fi
      tmux_add_pane "$session" "$cli" "" "$agent_workdir"
      local last_pane
      last_pane=$(tmux list-panes -t "$session" -F '#{pane_id}' | tail -1)
      pane_ids+=("$last_pane")
    done

    # Phase 2: Apply layout so all panes have proper size before CLI launch
    tmux_layout "$session" "${#manual_assignments[@]}" "$layout"
    sleep 0.5  # let tmux settle after layout change

    local session_dir="$SWARM_SESSIONS_DIR/$session"

    # Phase 3a: Launch all CLIs simultaneously + register pane mappings now
    # (register before CLI starts so title override by node/python doesn't break detection)
    for i in $(seq 0 $((${#manual_assignments[@]} - 1))); do
      local entry="${manual_assignments[$i]}"
      local cli="${entry%%:*}"
      local pane="${pane_ids[$i]}"
      cli_pane_launch "$cli" "$pane" "$auto_approve"
      pane_register "$session_dir" "$cli" "$pane"
    done

    # Phase 3b: Wait for ready and send tasks (CLIs already booting in parallel)
    for i in $(seq 0 $((${#manual_assignments[@]} - 1))); do
      local entry="${manual_assignments[$i]}"
      local cli="${entry%%:*}"
      local task="${entry#*:}"
      local pane="${pane_ids[$i]}"
      cli_wait_ready "$cli" "$pane"
      cli_send_task "$pane" "$task"
      cli_verify_submitted "$cli" "$pane" "$task"
    done
    state_save "$session" "$project" "$use_worktree" "$base_branch" "$layout" "${#manual_assignments[@]}" "" ""

    echo "Swarm '$session' 已启动（手动分配模式，${#manual_assignments[@]} 个 agent）。"
  else
    # TL mode: launch TL and let it analyze
    tmux select-pane -t "${session}:0.0" -T "TL:${tl_cli}" 2>/dev/null
    cli_pane_launch "$tl_cli" "${session}:0.0" "$auto_approve"

    # Build task list text
    local tasks_text=""
    for i in "${!tasks[@]}"; do
      tasks_text="${tasks_text}- 任务$((i+1)): ${tasks[$i]}"$'\n'
    done

    local context="Quick mode. Project: ${project:-none}"
    local tl_prompt
    tl_prompt=$(generate_tl_prompt "$available" "$tasks_text" "$context")

    sleep 2
    local prompt_file="$SWARM_HOME/tl-prompt-${session}.md"
    mkdir -p "$SWARM_HOME"
    echo "$tl_prompt" > "$prompt_file"
    tmux send-keys -t "${session}:0.0" -- "请阅读分析任务: $prompt_file" Enter

    local tl_pane_id
    tl_pane_id=$(tmux list-panes -t "${session}:0" -F '#{pane_id}' | head -1)
    state_save "$session" "$project" "$use_worktree" "$base_branch" "$layout" "1" "$tl_cli" "$tl_pane_id"

    echo "Swarm '$session' 已启动。TL ($tl_cli) 正在分析任务..."
    echo "确认分配后: telos-swarm add --<cli> \"任务\""
  fi

  echo ""
  hooks_fire "swarm_start"
  tmux_attach "$session"
}

cmd_add() {
  state_load || exit 1

  local cli="" task=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --claude|--gemini|--codex|--kimi)
        cli="${1#--}"; task="$2"; shift 2 ;;
      *)
        echo "用法: telos-swarm add --<cli> \"任务描述\"" >&2; exit 1 ;;
    esac
  done

  if [ -z "$cli" ] || [ -z "$task" ]; then
    echo "用法: telos-swarm add --<cli> \"任务描述\"" >&2
    exit 1
  fi

  # Check CLI available
  local available
  available=$(cli_detect)
  if ! echo "$available" | grep -qw "$cli"; then
    echo "CLI '$cli' 不可用。可用: $available" >&2
    exit 1
  fi

  if ! tmux_session_exists "$SWARM_SESSION"; then
    echo "Swarm session '$SWARM_SESSION' 不存在。" >&2
    exit 1
  fi

  # Create worktree if needed
  local workdir="${SWARM_PROJECT:-$HOME}"
  local agent_id="agent-$(date +%s)"
  if [ "$SWARM_WORKTREE" = "true" ] && [ -n "$SWARM_PROJECT" ] && [ -d "$SWARM_PROJECT" ]; then
    workdir=$(worktree_create "$SWARM_PROJECT" "$agent_id" "$SWARM_BASE_BRANCH" 2>/dev/null) || workdir="${SWARM_PROJECT:-$HOME}"
  fi

  # Add pane
  tmux_add_pane "$SWARM_SESSION" "${agent_id}:${cli}" "" "$workdir"
  sleep 1
  local last_pane
  last_pane=$(tmux list-panes -t "$SWARM_SESSION" -F '#{pane_id}' | tail -1)
  cli_pane_launch "$cli" "$last_pane"
  sleep 2
  cli_send_task "$last_pane" "$task"
  cli_verify_submitted "$cli" "$last_pane" "$task"

  # Register pane mapping for task dispatch
  if [ -n "${SWARM_SESSION_DIR:-}" ]; then
    pane_register "$SWARM_SESSION_DIR" "$cli" "$last_pane"
  fi

  # Update layout
  local pane_count
  pane_count=$(tmux_pane_count "$SWARM_SESSION")
  tmux_layout "$SWARM_SESSION" "$pane_count" "$SWARM_LAYOUT"
  state_update_pane_count

  echo "已添加 $cli agent (${agent_id})，当前 ${pane_count} 个 pane。"
}

cmd_status() {
  state_load || exit 1

  echo "=== telos-swarm status ==="
  echo "Session:   $SWARM_SESSION"
  echo "Project:   ${SWARM_PROJECT:-N/A}"
  echo "Worktree:  $SWARM_WORKTREE"
  echo "Branch:    $SWARM_BASE_BRANCH"
  echo "Layout:    $SWARM_LAYOUT"
  echo ""

  if tmux_session_exists "$SWARM_SESSION"; then
    echo "Panes:"
    tmux list-panes -t "$SWARM_SESSION" -F '  #{pane_index}: #{pane_title} (#{pane_current_command}) #{pane_width}x#{pane_height}'
  else
    echo "Session 不存在（可能已手动关闭）。"
  fi

  if [ "$SWARM_WORKTREE" = "true" ] && [ -n "$SWARM_PROJECT" ]; then
    echo ""
    echo "Worktrees:"
    worktree_list "$SWARM_PROJECT"
  fi
}

cmd_merge() {
  state_load || exit 1

  if [ "$SWARM_WORKTREE" != "true" ] || [ -z "$SWARM_PROJECT" ]; then
    echo "当前 swarm 未使用 worktree。" >&2
    exit 1
  fi

  local agent_id="${1:-}"

  if [ -z "$agent_id" ]; then
    echo "可用的 worktree:"
    worktree_list "$SWARM_PROJECT"
    echo ""
    read -p "输入要合并的 agent ID: " agent_id
  fi

  if [ -z "$agent_id" ]; then
    echo "未指定 agent ID。" >&2
    exit 1
  fi

  worktree_merge "$SWARM_PROJECT" "$agent_id" "$SWARM_BASE_BRANCH"
}

cmd_stop() {
  state_load || exit 1

  hooks_fire "swarm_stop"

  if tmux_session_exists "$SWARM_SESSION"; then
    echo "停止 swarm session: $SWARM_SESSION"
    tmux_kill_session "$SWARM_SESSION"
    echo "Session 已终止。Worktree 保留（如有）。"
  else
    echo "Session 已不存在。"
  fi

  state_clear
}

cmd_clean() {
  state_load 2>/dev/null || true

  # Stop session if running
  if [ -n "${SWARM_SESSION:-}" ] && tmux_session_exists "$SWARM_SESSION"; then
    echo "停止 session: $SWARM_SESSION"
    tmux_kill_session "$SWARM_SESSION"
  fi

  # Clean worktrees
  if [ -n "${SWARM_PROJECT:-}" ] && [ -d "${SWARM_PROJECT:-}" ]; then
    worktree_clean "$SWARM_PROJECT"
  fi

  # Clean session directory
  if [ -n "${SWARM_SESSION_DIR:-}" ] && [ -d "${SWARM_SESSION_DIR:-}" ]; then
    echo "清理 session 目录: $SWARM_SESSION_DIR"
    rm -rf "$SWARM_SESSION_DIR"
  fi

  state_clear
  echo "清理完成。"
}

cmd_task() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true

  state_load || exit 1
  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session（缺少 SWARM_SESSION_DIR）。请先启动 swarm。" >&2
    exit 1
  fi

  case "$subcmd" in
    add)
      local task_type="" assigned_cli="" depends_on="" mode="solo" task_desc=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --type)    task_type="$2"; shift 2 ;;
          --assign)  assigned_cli="$2"; shift 2 ;;
          --depends) depends_on="$2"; shift 2 ;;
          --mode)    mode="$2"; shift 2 ;;
          -*)        echo "未知选项: $1" >&2; exit 1 ;;
          *)         task_desc="$1"; shift ;;
        esac
      done
      # Handle "claude:team" shorthand
      if echo "$assigned_cli" | grep -q ':team$'; then
        assigned_cli="${assigned_cli%:team}"
        mode="team"
      fi
      if [ -z "$task_type" ] || [ -z "$assigned_cli" ] || [ -z "$task_desc" ]; then
        echo "用法: telos-swarm task add --type <type> --assign <cli> [--depends id,id] [--mode solo|team] \"描述\"" >&2
        exit 1
      fi
      local tid
      tid=$(task_create "$session_dir" "$task_type" "$task_desc" "$assigned_cli" "$depends_on" "$mode")
      echo "已创建任务 ${tid}: ${task_desc}"
      ;;
    list)
      local json_flag=""
      [ "${1:-}" = "--json" ] && json_flag="--json"
      task_list "$session_dir" "$json_flag"
      ;;
    get)
      local task_id="${1:-}"
      if [ -z "$task_id" ]; then
        echo "用法: telos-swarm task get <task_id> [--json]" >&2; exit 1
      fi
      local json_flag=""
      [ "${2:-}" = "--json" ] && json_flag="--json"
      task_get "$session_dir" "$task_id" "$json_flag"
      ;;
    dispatch)
      local task_id="${1:-}"
      if [ -n "$task_id" ]; then
        _lock_acquire "$session_dir" || exit 1
        trap '_lock_release "'"$session_dir"'"' RETURN INT TERM
        task_dispatch "$session_dir" "$task_id" "$SWARM_SESSION" || true
      else
        task_dispatch_ready "$session_dir" "$SWARM_SESSION"
      fi
      ;;
    poll)
      local timeout="${1:-300}"
      shift 2>/dev/null || true
      task_poll "$session_dir" "$timeout" "$@"
      ;;
    status)
      task_status "$session_dir"
      ;;
    retry)
      local task_id="${1:-}"
      if [ -z "$task_id" ]; then
        echo "用法: telos-swarm task retry <task_id>" >&2; exit 1
      fi
      task_retry "$session_dir" "$task_id" "$SWARM_SESSION"
      ;;
    cancel)
      local task_id="${1:-}"
      if [ -z "$task_id" ]; then
        echo "用法: telos-swarm task cancel <task_id|all> [--force]" >&2; exit 1
      fi
      local force_flag=""
      [ "${2:-}" = "--force" ] && force_flag="--force"
      task_cancel "$session_dir" "$task_id" "$force_flag"
      ;;
    *)
      echo "用法: telos-swarm task <add|list|get|dispatch|poll|status|retry|cancel>" >&2
      exit 1
      ;;
  esac
}

cmd_arena() {
  state_load || exit 1
  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session。请先启动 swarm。" >&2
    exit 1
  fi

  local clis=() topic="" auto_run=false rounds=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        auto_run=true; shift ;;
      --rounds)
        if [ $# -lt 2 ]; then
          echo "--rounds 需要一个参数" >&2; exit 1
        fi
        rounds="$2"; shift 2
        if ! [[ "$rounds" =~ ^[1-9][0-9]*$ ]]; then
          echo "--rounds 必须为正整数，当前值: $rounds" >&2; exit 1
        fi
        ;;
      --claude|--gemini|--codex|--kimi)
        clis+=("${1#--}"); shift ;;
      -*)
        echo "未知选项: $1" >&2; exit 1 ;;
      *)
        topic="$1"; shift ;;
    esac
  done

  if [ ${#clis[@]} -lt 2 ]; then
    echo "Arena 至少需要 2 个 CLI。用法: telos-swarm arena --claude --gemini \"议题\"" >&2
    exit 1
  fi
  if [ -z "$topic" ]; then
    echo "请提供议题。用法: telos-swarm arena --claude --gemini \"议题\"" >&2
    exit 1
  fi

  # Write shared context
  echo "## Arena Topic

${topic}" > "$session_dir/.swarm/context.md"

  echo "=== Arena: ${topic} ==="
  echo "参与者: ${clis[*]}"
  echo ""

  local round=1
  local prev_synth_output=""

  while [ "$round" -le "$rounds" ]; do
    if [ "$rounds" -gt 1 ]; then
      echo "--- Round ${round}/${rounds} ---"
      echo ""
    fi

    # Update context with previous round's synthesis
    if [ -n "$prev_synth_output" ] && [ -f "$prev_synth_output" ]; then
      local prev_content
      prev_content=$(grep -v '<!-- SWARM:DONE -->' "$prev_synth_output")
      echo "## Arena Topic

${topic}

## Previous Round Synthesis

${prev_content}" > "$session_dir/.swarm/context.md"
    fi

    # Phase 1: Analysis (each CLI analyzes independently)
    local analysis_ids=()
    local round_suffix=""
    [ "$rounds" -gt 1 ] && round_suffix=" (R${round})"
    for cli in "${clis[@]}"; do
      local tid
      tid=$(task_create "$session_dir" "analysis" "分析议题「${topic}」，给出你的观点和方案${round_suffix}" "$cli")
      analysis_ids+=("$tid")
      echo "  创建分析任务 ${tid} → ${cli}"
    done

    # Phase 2: Cross-review (each CLI reviews the other's analysis)
    local review_ids=()
    for i in "${!clis[@]}"; do
      local reviewer="${clis[$i]}"
      local peer_idx=$(( (i + 1) % ${#clis[@]} ))
      local peer_id="${analysis_ids[$peer_idx]}"
      local peer_cli="${clis[$peer_idx]}"
      local tid
      tid=$(task_create "$session_dir" "review" "审查 ${peer_cli} 对「${topic}」的分析${round_suffix}" "$reviewer" "$peer_id")
      review_ids+=("$tid")
      echo "  创建审查任务 ${tid} → ${reviewer} (审查 ${peer_cli} 的 ${peer_id})"
    done

    # Phase 3: Synthesis (first CLI synthesizes all reviews)
    local all_review_deps
    all_review_deps=$(IFS=,; echo "${review_ids[*]}")
    local synth_id
    synth_id=$(task_create "$session_dir" "synthesis" "综合所有分析和审查，生成最终结论：「${topic}」${round_suffix}" "${clis[0]}" "$all_review_deps")
    echo "  创建综合任务 ${synth_id} → ${clis[0]}"

    prev_synth_output="$session_dir/.swarm/outputs/${synth_id}.md"

    if [ "$auto_run" = "true" ]; then
      echo ""
      echo "自动运行 Round ${round}..."
      task_dispatch_ready "$session_dir" "$SWARM_SESSION"
      task_poll "$session_dir" 300
    fi

    round=$((round + 1))
    [ "$round" -le "$rounds" ] && echo ""
  done

  echo ""
  if [ "$auto_run" = "true" ]; then
    echo "Arena 完成（${rounds} 轮）。产出文件："
    for f in "$session_dir/.swarm/outputs"/*.md; do
      [ -f "$f" ] && echo "  $(basename "$f")"
    done
    hooks_fire "arena_complete" "SWARM_METADATA={\"template\":\"arena\",\"rounds\":${rounds}}"
    return 0
  fi

  echo "任务链已创建（${rounds} 轮）。运行以下命令推进："
  echo "  telos-swarm task dispatch   # 分发就绪任务"
  echo "  telos-swarm task poll       # 等待完成（自动推进依赖链）"
}

cmd_brainstorm() {
  state_load || exit 1
  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session。请先启动 swarm。" >&2
    exit 1
  fi

  local clis=() topic="" auto_run=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        auto_run=true; shift ;;
      --claude|--gemini|--codex|--kimi)
        clis+=("${1#--}"); shift ;;
      -*)
        echo "未知选项: $1" >&2; exit 1 ;;
      *)
        topic="$1"; shift ;;
    esac
  done

  if [ ${#clis[@]} -lt 2 ]; then
    echo "Brainstorm 至少需要 2 个 CLI。" >&2
    exit 1
  fi
  if [ -z "$topic" ]; then
    echo "请提供议题。" >&2
    exit 1
  fi

  echo "## Brainstorm Topic

${topic}" > "$session_dir/.swarm/context.md"

  echo "=== Brainstorm: ${topic} ==="
  echo "参与者: ${clis[*]}"
  echo ""

  # Phase 1: Independent analysis (all CLIs)
  local analysis_ids=()
  for cli in "${clis[@]}"; do
    local tid
    tid=$(task_create "$session_dir" "analysis" "头脑风暴：「${topic}」，给出你的创意和方案" "$cli")
    analysis_ids+=("$tid")
    echo "  创建分析任务 ${tid} → ${cli}"
  done

  # Phase 2: Synthesis (first CLI, depends on all analyses)
  local all_deps
  all_deps=$(IFS=,; echo "${analysis_ids[*]}")
  local synth_id
  synth_id=$(task_create "$session_dir" "synthesis" "综合所有头脑风暴结果，提炼最佳方案：「${topic}」" "${clis[0]}" "$all_deps")
  echo "  创建综合任务 ${synth_id} → ${clis[0]}"

  echo ""

  if [ "$auto_run" = "true" ]; then
    echo "自动运行模式：开始分发和轮询..."
    task_dispatch_ready "$session_dir" "$SWARM_SESSION"
    task_poll "$session_dir" 300
    echo ""
    echo "Brainstorm 完成。产出文件："
    for f in "$session_dir/.swarm/outputs"/*.md; do
      [ -f "$f" ] && echo "  $(basename "$f")"
    done
    hooks_fire "arena_complete" "SWARM_METADATA={\"template\":\"brainstorm\"}"
    return 0
  fi

  echo "任务链已创建。运行以下命令推进："
  echo "  telos-swarm task dispatch && telos-swarm task poll"
}

cmd_pair() {
  state_load || exit 1
  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session。请先启动 swarm。" >&2
    exit 1
  fi

  local clis=() task_desc="" auto_run=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        auto_run=true; shift ;;
      --claude|--gemini|--codex|--kimi)
        clis+=("${1#--}"); shift ;;
      -*)
        echo "未知选项: $1" >&2; exit 1 ;;
      *)
        task_desc="$1"; shift ;;
    esac
  done

  if [ ${#clis[@]} -ne 2 ]; then
    echo "Pair 需要恰好 2 个 CLI（第一个编码，第二个审查）。" >&2
    exit 1
  fi
  if [ -z "$task_desc" ]; then
    echo "请提供任务描述。" >&2
    exit 1
  fi

  local coder="${clis[0]}" reviewer="${clis[1]}"

  echo "## Pair Programming Task

${task_desc}" > "$session_dir/.swarm/context.md"

  echo "=== Pair: ${task_desc} ==="
  echo "Coder: ${coder} | Reviewer: ${reviewer}"
  echo ""

  # Phase 1: Coding
  local code_id
  code_id=$(task_create "$session_dir" "coding" "实现：${task_desc}" "$coder")
  echo "  创建编码任务 ${code_id} → ${coder}"

  # Phase 2: Review
  local review_id
  review_id=$(task_create "$session_dir" "review" "审查 ${coder} 的实现：${task_desc}" "$reviewer" "$code_id")
  echo "  创建审查任务 ${review_id} → ${reviewer}"

  # Phase 3: Revision
  local revise_id
  revise_id=$(task_create "$session_dir" "coding" "根据 ${reviewer} 的审查意见修订实现：${task_desc}" "$coder" "$review_id")
  echo "  创建修订任务 ${revise_id} → ${coder}"

  echo ""

  if [ "$auto_run" = "true" ]; then
    echo "自动运行模式：开始分发和轮询..."
    task_dispatch_ready "$session_dir" "$SWARM_SESSION"
    task_poll "$session_dir" 600
    echo ""
    echo "Pair 完成。产出文件："
    for f in "$session_dir/.swarm/outputs"/*.md; do
      [ -f "$f" ] && echo "  $(basename "$f")"
    done
    hooks_fire "arena_complete" "SWARM_METADATA={\"template\":\"pair\"}"
    return 0
  fi

  echo "任务链已创建。运行以下命令推进："
  echo "  telos-swarm task dispatch && telos-swarm task poll"
}

cmd_tl() {
  local auto_run=false
  local user_intent=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --auto) auto_run=true; shift ;;
      -*) echo "未知选项: $1" >&2; exit 1 ;;
      *) user_intent="$1"; shift ;;
    esac
  done

  if [ -z "$user_intent" ]; then
    echo "用法: telos-swarm tl [--auto] \"用户意图描述\"" >&2
    exit 1
  fi

  # Load or create session
  if ! state_load 2>/dev/null; then
    # Auto-create a quick session
    check_deps
    local available
    available=$(cli_detect)
    if [ -z "$available" ]; then
      echo "未检测到任何可用的 AI CLI。" >&2
      exit 1
    fi

    local session="swarm-$(date +%H%M%S)"
    local workdir="$HOME"
    tmux_session_exists "$session" && tmux_kill_session "$session"
    tmux_create_session "$session" "$workdir"

    # Launch CLIs in panes
    local cli_list=($available)
    local first_cli="${cli_list[0]}"
    tmux select-pane -t "${session}:0.0" -T "${first_cli}" 2>/dev/null
    cli_pane_launch "$first_cli" "${session}:0.0"

    for i in $(seq 1 $((${#cli_list[@]} - 1))); do
      local cli="${cli_list[$i]}"
      tmux_add_pane "$session" "$cli" "" "$workdir"
      local last_pane
      last_pane=$(tmux list-panes -t "$session" -F '#{pane_id}' | tail -1)
      cli_pane_launch "$cli" "$last_pane"
    done

    local pane_count=${#cli_list[@]}
    tmux_layout "$session" "$pane_count" "auto"
    local tl_pane_id
    tl_pane_id=$(tmux list-panes -t "${session}:0" -F '#{pane_id}' | head -1)
    state_save "$session" "" "false" "main" "auto" "$pane_count" "$first_cli" "$tl_pane_id"

    local session_dir="$SWARM_SESSIONS_DIR/$session"
    pane_auto_detect "$session_dir" "$session"

    # Reload state
    state_load
    echo "自动创建 swarm session: $session (${available})"
  fi

  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session。" >&2
    exit 1
  fi

  # Detect available CLIs
  local available
  available=$(cli_detect)

  # Generate TL prompt with user intent as the task
  local tl_prompt
  tl_prompt=$(generate_tl_prompt "$available" "用户意图: ${user_intent}" "TL 模式。请分析用户意图并用 telos-swarm task add 命令创建任务链。")

  # Write prompt to file
  local prompt_file="$session_dir/.swarm/prompts/tl-intent.md"
  echo "$tl_prompt" > "$prompt_file"

  echo "=== TL 分析模式 ==="
  echo "用户意图: ${user_intent}"
  echo "TL prompt: ${prompt_file}"
  echo ""

  # Find TL pane (first pane in session)
  local tl_pane
  tl_pane=$(tmux list-panes -t "$SWARM_SESSION" -F '#{pane_id}' 2>/dev/null | head -1)

  if [ -z "$tl_pane" ]; then
    echo "找不到 TL pane。请确保 swarm session 正在运行。" >&2
    exit 1
  fi

  # Send to TL
  local instruction="阅读 ${prompt_file}，分析用户意图并用 Bash 调用 telos-swarm task add 创建任务链"
  if [ "$auto_run" = "true" ]; then
    instruction="${instruction}，创建完成后自动执行 telos-swarm task dispatch 和 telos-swarm task poll 600"
  fi
  cli_send_task "$tl_pane" "$instruction"

  # Detect TL CLI from pane title for verification
  local tl_cli_name
  tl_cli_name=$(tmux display-message -t "$tl_pane" -p '#{pane_title}' 2>/dev/null | sed 's/.*://' | head -1)
  cli_verify_submitted "${tl_cli_name:-unknown}" "$tl_pane" "$instruction"

  echo "已发送给 TL。"
  if [ "$auto_run" = "true" ]; then
    echo "TL 将自动创建任务 → dispatch → poll。"
  else
    echo "TL 将创建任务链，等待你确认后手动 dispatch。"
  fi
}

cmd_archive() {
  state_load || exit 1
  local session_dir="${SWARM_SESSION_DIR:-}"
  if [ -z "$session_dir" ]; then
    echo "没有活跃的 session。" >&2
    exit 1
  fi

  local move_mode=false
  [ "${1:-}" = "--move" ] && move_mode=true

  local vault_dir="${SWARM_PROJECT:-$HOME}"
  local archive_dir="$vault_dir/.swarm-archive/$(basename "$session_dir")"
  mkdir -p "$archive_dir"

  if [ "$move_mode" = "true" ]; then
    mv "$session_dir/.swarm" "$archive_dir/"
    echo "已移动 .swarm → $archive_dir/"
  else
    cp -r "$session_dir/.swarm" "$archive_dir/"
    echo "已复制 .swarm → $archive_dir/ (原件保留在 $session_dir)"
  fi
}

cmd_help() {
  cat <<'EOF'
telos-swarm — Multi-CLI AI agent orchestrator

用法:
  telos-swarm start <config.yaml>     从 YAML 配置启动 swarm
  telos-swarm quick [选项] "任务"...   快捷模式启动
  telos-swarm add --<cli> "任务"       向运行中的 swarm 追加 agent
  telos-swarm status                   显示当前 swarm 状态
  telos-swarm merge [agent_id]         交互式合并 worktree 分支
  telos-swarm stop                     终止 session（保留 worktree）
  telos-swarm clean                    清理 session + worktree

  telos-swarm task add --type <type> --assign <cli> [--depends id,id] "描述"
  telos-swarm task list                列出所有任务
  telos-swarm task get <id>            查看任务详情
  telos-swarm task dispatch [id]       分发就绪任务（或指定任务）
  telos-swarm task poll [timeout]      轮询等待任务完成
  telos-swarm task status              任务状态总览
  telos-swarm task retry <id>          重试失败的任务

  telos-swarm tl [--auto] "意图"          TL 分析意图并自动创建任务链
  telos-swarm arena [--auto] [--rounds N] --<cli1> --<cli2> "议题"   Arena 辩论模式
  telos-swarm brainstorm [--auto] --<cli>... "议题"     头脑风暴（跳过交叉审查）
  telos-swarm pair [--auto] --<coder> --<reviewer> "任务"  结对编程
  telos-swarm archive [--move]         归档产出到项目目录

Task 类型: coding | analysis | review | code_review | design | synthesis | free
Assign 支持: claude | gemini | codex | kimi（加 :team 启用子 agent）

Quick 模式选项:
  --tl <cli>              指定 TL (默认自动选择)
  --project <path>        项目目录
  --base <branch>         基础分支 (默认 main)
  --no-worktree           不使用 worktree 隔离
  --layout grid|stack|auto  布局模式 (默认 auto)
  --auto-approve          以自动批准模式启动 CLI（跳过权限确认）

Arena 选项:
  --auto                  创建任务链后自动分发和轮询
  --rounds N              Arena 多轮辩论（默认 1）

Agent 分配:
  --claude "任务"         手动分配给 claude
  --gemini "任务"         手动分配给 gemini
  --codex "任务"          手动分配给 codex
  --kimi "任务"           手动分配给 kimi

示例:
  # 手动任务分配
  telos-swarm quick --claude "待命" --gemini "待命"
  telos-swarm task add --type coding --assign claude "设计数据模型"
  telos-swarm task add --type review --assign gemini --depends 001 "审查数据模型"
  telos-swarm task dispatch
  telos-swarm task poll

  # Arena 辩论
  telos-swarm arena --auto --claude --gemini "evidence chain 怎么设计"

  # 头脑风暴
  telos-swarm brainstorm --auto --claude --gemini --kimi "产品命名"

  # 结对编程
  telos-swarm pair --auto --claude --codex "实现用户认证模块"

  # Claude 子 agent 模式
  telos-swarm task add --type coding --assign claude:team "用子 agent 并行实现"

依赖: tmux, git, yq (brew install yq)
EOF
}

# ─── Main ─────────────────────────────────────────────────────

main() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    start)   cmd_start "$@" ;;
    quick)   cmd_quick "$@" ;;
    add)     cmd_add "$@" ;;
    status)  cmd_status ;;
    merge)   cmd_merge "$@" ;;
    stop)    cmd_stop ;;
    clean)   cmd_clean ;;
    task)    cmd_task "$@" ;;
    tl)      cmd_tl "$@" ;;
    arena)      cmd_arena "$@" ;;
    brainstorm) cmd_brainstorm "$@" ;;
    pair)       cmd_pair "$@" ;;
    archive)    cmd_archive "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "未知命令: $cmd" >&2
      echo "使用 'telos-swarm help' 查看帮助。" >&2
      exit 1
      ;;
  esac
}

main "$@"
