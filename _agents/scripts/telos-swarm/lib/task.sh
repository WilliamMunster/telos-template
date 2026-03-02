#!/bin/bash
# task.sh — Task file protocol: CRUD, dispatch, poll, failover
# Source this file from telos-swarm.sh

# ─── Locking ──────────────────────────────────────────────────

_lock_acquire() {
  local session_dir="$1"
  local lock_dir="$session_dir/.swarm/.lock"

  # Auto-release stale lock (default 60s, override via SWARM_LOCK_STALE_SEC)
  if [ -d "$lock_dir" ]; then
    local lock_time
    lock_time=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local stale_sec="${SWARM_LOCK_STALE_SEC:-60}"
    if [ $((now - lock_time)) -gt "$stale_sec" ]; then
      rmdir "$lock_dir" 2>/dev/null
    fi
  fi

  # Try to acquire
  if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "[task] 另一个操作正在进行中，请稍后再试。" >&2
    return 1
  fi
}

_lock_release() {
  local session_dir="$1"
  rmdir "$session_dir/.swarm/.lock" 2>/dev/null
}

# ─── Helpers ──────────────────────────────────────────────────

# Resolve OUTPUT_FILE to absolute path (compatible with both relative and absolute)
_resolve_output_path() {
  local session_dir="$1" output="$2"
  [[ "$output" = /* ]] && echo "$output" || echo "$session_dir/$output"
}

_swarm_dir() {
  local session_dir="$1"
  echo "$session_dir/.swarm"
}

_next_task_id() {
  local tasks_dir="$1"
  local max=0
  local files
  files=$(ls "$tasks_dir"/*.env 2>/dev/null) || true
  for f in $files; do
    [ -f "$f" ] || continue
    local num
    num=$(basename "$f" .env)
    num=$((10#$num))  # strip leading zeros
    [ "$num" -gt "$max" ] && max="$num"
  done
  printf "%03d" $((max + 1))
}

# Safe key-value reader — no shell eval, immune to injection
_task_read_field() {
  local file="$1" key="$2"
  grep "^${key}=" "$file" 2>/dev/null | head -1 | sed 's/^[^=]*="//; s/"$//; s/\\"/"/g'
}

_task_source() {
  local task_file="$1"
  TASK_ID=$(_task_read_field "$task_file" "TASK_ID")
  TASK_TYPE=$(_task_read_field "$task_file" "TASK_TYPE")
  TASK_DESC=$(_task_read_field "$task_file" "TASK_DESC")
  ASSIGNED_CLI=$(_task_read_field "$task_file" "ASSIGNED_CLI")
  MODE=$(_task_read_field "$task_file" "MODE")
  DEPENDS_ON=$(_task_read_field "$task_file" "DEPENDS_ON")
  STATUS=$(_task_read_field "$task_file" "STATUS")
  OUTPUT_FILE=$(_task_read_field "$task_file" "OUTPUT_FILE")
  QUALITY=$(_task_read_field "$task_file" "QUALITY")
}

_check_depends_done() {
  local session_dir="$1" depends_on="$2"
  [ -z "$depends_on" ] && return 0

  local IFS=','
  for dep in $depends_on; do
    dep=$(echo "$dep" | tr -d ' ')
    local dep_file="$session_dir/.swarm/tasks/${dep}.env"
    if [ ! -f "$dep_file" ]; then
      return 1
    fi
    local dep_status=""
    dep_status=$(grep '^STATUS=' "$dep_file" | cut -d'"' -f2)
    # done or cancelled both unblock downstream
    if [ "$dep_status" != "done" ] && [ "$dep_status" != "cancelled" ]; then
      return 1
    fi
  done
  return 0
}

_generate_prompt() {
  local session_dir="$1" task_id="$2" task_type="$3" task_desc="$4" output_file="$5"

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local prompt_file="$swarm_dir/prompts/${task_id}.md"
  local context_file="$swarm_dir/context.md"

  local context=""
  [ -f "$context_file" ] && context=$(cat "$context_file")

  local type_instructions=""
  case "$task_type" in
    coding)
      type_instructions="- Write clean, working code
- Include brief inline comments for non-obvious logic" ;;
    analysis)
      type_instructions="- Provide structured analysis with clear sections
- Support claims with reasoning" ;;
    review)
      type_instructions="- List what you agree with and why
- Identify logical gaps or missing perspectives
- Provide actionable improvement suggestions" ;;
    code_review)
      type_instructions="- Read each file and review the actual source code line by line
- Do NOT review or critique this task description itself
- For each issue found, report: file path + line number + problem + suggested fix
- Classify issues as CRITICAL / WARNING / INFO" ;;
    design)
      type_instructions="- Present the design with clear rationale
- Consider trade-offs and alternatives" ;;
    synthesis)
      type_instructions="- Integrate inputs from all sources
- Resolve contradictions, highlight consensus
- Produce a unified recommendation" ;;
    *)
      type_instructions="- Complete the task as described" ;;
  esac

  # Use template file if available, otherwise inline
  local template="$TMPL_DIR/task-prompt.md"
  if [ -f "$template" ]; then
    local content
    content=$(cat "$template")
    content="${content//\{\{description\}\}/$task_desc}"
    content="${content//\{\{context\}\}/${context:-No additional context provided.}}"
    content="${content//\{\{output_path\}\}/$output_file}"
    content="${content//\{\{type_specific_instructions\}\}/$type_instructions}"
    echo "$content" > "$prompt_file"
  else
    cat > "$prompt_file" <<EOF
## Task

${task_desc}

## Context

${context:-No additional context provided.}

## Output Requirements

Write your result to \`${output_file}\`

${type_instructions}

CRITICAL: You MUST append \`<!-- SWARM:DONE -->\` as the very last line of your output file.
EOF
  fi

  echo "$prompt_file"
}

_generate_review_prompt() {
  local session_dir="$1" task_id="$2" task_desc="$3" output_file="$4" peer_ids="$5"

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local prompt_file="$swarm_dir/prompts/${task_id}.md"
  local context_file="$swarm_dir/context.md"

  local context=""
  [ -f "$context_file" ] && context=$(cat "$context_file")

  local peer_outputs=""
  local IFS=','
  for pid in $peer_ids; do
    pid=$(echo "$pid" | tr -d ' ')
    local peer_output_file="$swarm_dir/outputs/${pid}.md"
    if [ -f "$peer_output_file" ]; then
      local peer_cli=""
      local peer_task_file="$swarm_dir/tasks/${pid}.env"
      [ -f "$peer_task_file" ] && peer_cli=$(grep '^ASSIGNED_CLI=' "$peer_task_file" | cut -d'"' -f2)
      peer_outputs="${peer_outputs}### Output from ${peer_cli:-agent} (task ${pid})

$(cat "$peer_output_file")

---

"
    fi
  done

  # Use template file if available, otherwise inline
  local template="$TMPL_DIR/review-prompt.md"
  if [ -f "$template" ]; then
    local content
    content=$(cat "$template")
    content="${content//\{\{peer_cli\}\}/${peer_cli:-peer agent}}"
    content="${content//\{\{peer_output\}\}/${peer_outputs:-No peer outputs available yet.}}"
    content="${content//\{\{output_path\}\}/$output_file}"
    echo "$content" > "$prompt_file"
  else
    cat > "$prompt_file" <<EOF
## Review Task

${task_desc}

## Peer Outputs to Review

${peer_outputs:-No peer outputs available yet.}

## Context

${context:-No additional context provided.}

## Review Requirements

1. What you agree with and why
2. Logical gaps or missing perspectives
3. Actionable improvement suggestions

Write your review to \`${output_file}\`

CRITICAL: You MUST append \`<!-- SWARM:DONE -->\` as the very last line of your output file.
EOF
  fi

  echo "$prompt_file"
}

# ─── Quality Gate ────────────────────────────────────────────

task_check_quality() {
  local session_dir="$1" task_id="$2"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"
  local task_type
  task_type=$(_task_read_field "$task_file" "TASK_TYPE")
  local output_file
  output_file=$(_task_read_field "$task_file" "OUTPUT_FILE")
  local abs_output
  abs_output=$(_resolve_output_path "$session_dir" "$output_file")

  if [ ! -f "$abs_output" ]; then
    echo "no_output"
    return 0
  fi

  # Strip DONE marker for content analysis
  local content
  content=$(grep -v '<!-- SWARM:DONE -->' "$abs_output")
  local line_count
  line_count=$(echo "$content" | wc -l | tr -d ' ')

  # Minimum line count — configurable via SWARM_QUALITY_MIN_LINES
  local min_lines=${SWARM_QUALITY_MIN_LINES:-3}
  [ "$task_type" = "coding" ] && min_lines=$((min_lines + 2))
  if [ "$line_count" -lt "$min_lines" ]; then
    echo "fail:too_short(${line_count}<${min_lines})"
    return 0
  fi

  # Structure checks by type
  case "$task_type" in
    analysis|synthesis)
      local heading_count
      heading_count=$(echo "$content" | grep -c '^## ' || true)
      if [ "$heading_count" -lt 2 ]; then
        echo "fail:missing_headings(${heading_count}<2)"
        return 0
      fi
      ;;
    review)
      local heading_count
      heading_count=$(echo "$content" | grep -c '^## ' || true)
      if [ "$heading_count" -lt 2 ]; then
        echo "fail:missing_headings(${heading_count}<2)"
        return 0
      fi
      # Must have bullet points or numbered list
      local list_count
      list_count=$(echo "$content" | grep -cE '^[[:space:]]*([-*]|[0-9]+\.) ' || true)
      if [ "$list_count" -lt 1 ]; then
        echo "fail:missing_list_items"
        return 0
      fi
      ;;
  esac

  # Error pattern detection — configurable via SWARM_QUALITY_ERROR_PATTERNS
  local error_patterns="${SWARM_QUALITY_ERROR_PATTERNS:-^(I cannot |I am unable to |抱歉，我无法|对不起，我不能)}"
  if echo "$content" | grep -qE "$error_patterns"; then
    echo "fail:error_pattern_detected"
    return 0
  fi

  echo "pass"
}

# ─── Task CRUD ────────────────────────────────────────────────

task_create() {
  local session_dir="$1" task_type="$2" task_desc="$3" assigned_cli="$4"
  local depends_on="${5:-}" mode="${6:-solo}"

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  mkdir -p "$swarm_dir/tasks" "$swarm_dir/prompts" "$swarm_dir/outputs"

  local task_id
  task_id=$(_next_task_id "$swarm_dir/tasks")
  local output_file=".swarm/outputs/${task_id}.md"

  # Sanitize values: escape double quotes and strip newlines for .env
  local safe_desc safe_type safe_cli safe_mode safe_deps
  safe_desc=$(printf '%s' "$task_desc" | tr '\n' ' ' | sed 's/"/\\"/g')
  # Preserve original desc with newlines for prompt generation (only escape quotes)
  local prompt_desc
  prompt_desc=$(printf '%s' "$task_desc" | sed 's/"/\\"/g')
  safe_type=$(printf '%s' "$task_type" | tr -cd 'a-z_')
  safe_cli=$(printf '%s' "$assigned_cli" | tr -cd 'a-z')
  safe_mode=$(printf '%s' "$mode" | tr -cd 'a-z')
  safe_deps=$(printf '%s' "$depends_on" | tr -cd '0-9,')

  # Reject empty required fields after sanitization
  if [ -z "$safe_type" ] || [ -z "$safe_cli" ]; then
    echo "[task_create] 错误: 净化后 type 或 cli 为空 (type='$safe_type', cli='$safe_cli')" >&2
    return 1
  fi

  local created_at
  created_at=$(date +%s)
  cat > "$swarm_dir/tasks/${task_id}.env" <<EOF
TASK_ID="${task_id}"
TASK_TYPE="${safe_type}"
TASK_DESC="${safe_desc}"
ASSIGNED_CLI="${safe_cli}"
MODE="${safe_mode}"
DEPENDS_ON="${safe_deps}"
STATUS="pending"
OUTPUT_FILE="${output_file}"
QUALITY="pending"
CREATED_AT="${created_at}"
EOF

  # Generate prompt based on type — use safe_type to match .env metadata
  # Prompts use absolute paths so CLIs can write output regardless of cwd
  local abs_output
  abs_output=$(_resolve_output_path "$session_dir" "$output_file")
  if [ "$safe_type" = "review" ] && [ -n "$depends_on" ]; then
    _generate_review_prompt "$session_dir" "$task_id" "$prompt_desc" "$abs_output" "$safe_deps" >/dev/null
  else
    _generate_prompt "$session_dir" "$task_id" "$safe_type" "$prompt_desc" "$abs_output" >/dev/null
  fi

  echo "$task_id"
}

task_list() {
  local session_dir="$1"
  local json_mode=false
  [ "${2:-}" = "--json" ] && json_mode=true

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")

  if [ ! -d "$swarm_dir/tasks" ] || [ -z "$(ls "$swarm_dir/tasks/"*.env 2>/dev/null)" ]; then
    if [ "$json_mode" = "true" ]; then
      echo "[]"
    else
      echo "没有任务。"
    fi
    return 0
  fi

  if [ "$json_mode" = "true" ]; then
    local first=true
    echo "["
    for f in "$swarm_dir/tasks"/*.env; do
      [ -f "$f" ] || continue
      _task_source "$f"
      local quality
      quality=$(_task_read_field "$f" "QUALITY")
      [ "$first" = "true" ] && first=false || echo ","
      printf '{"id":"%s","type":"%s","cli":"%s","mode":"%s","status":"%s","quality":"%s","depends":"%s"}' \
        "$TASK_ID" "$TASK_TYPE" "$ASSIGNED_CLI" "$MODE" "$STATUS" "${quality:-pending}" "${DEPENDS_ON:-}"
    done
    echo ""
    echo "]"
  else
    printf "%-5s %-10s %-10s %-8s %-8s %-10s %s\n" "ID" "TYPE" "CLI" "MODE" "STATUS" "QUALITY" "DEPENDS"
    printf "%-5s %-10s %-10s %-8s %-8s %-10s %s\n" "---" "----" "---" "----" "------" "-------" "-------"
    for f in "$swarm_dir/tasks"/*.env; do
      [ -f "$f" ] || continue
      _task_source "$f"
      local quality
      quality=$(_task_read_field "$f" "QUALITY")
      printf "%-5s %-10s %-10s %-8s %-8s %-10s %s\n" "$TASK_ID" "$TASK_TYPE" "$ASSIGNED_CLI" "$MODE" "$STATUS" "${quality:-—}" "${DEPENDS_ON:-—}"
    done
  fi
}

task_get() {
  local session_dir="$1" task_id="$2"
  local json_mode=false
  [ "${3:-}" = "--json" ] && json_mode=true

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"

  if [ ! -f "$task_file" ]; then
    echo "任务 ${task_id} 不存在。" >&2
    return 1
  fi

  _task_source "$task_file"
  local quality
  quality=$(_task_read_field "$task_file" "QUALITY")

  local abs_output
  abs_output=$(_resolve_output_path "$session_dir" "$OUTPUT_FILE")
  local output_exists=false
  local done_marker=false
  if [ -f "$abs_output" ]; then
    output_exists=true
    local last_line
    last_line=$(tail -1 "$abs_output")
    [ "$last_line" = "<!-- SWARM:DONE -->" ] && done_marker=true
  fi

  if [ "$json_mode" = "true" ]; then
    # Re-escape double quotes in desc for valid JSON
    local safe_desc="${TASK_DESC//\"/\\\"}"
    printf '{"id":"%s","type":"%s","desc":"%s","cli":"%s","mode":"%s","status":"%s","depends":"%s","output_file":"%s","quality":"%s","output_exists":%s,"done_marker":%s}\n' \
      "$TASK_ID" "$TASK_TYPE" "$safe_desc" "$ASSIGNED_CLI" "$MODE" "$STATUS" "${DEPENDS_ON:-}" "$OUTPUT_FILE" "${quality:-pending}" "$output_exists" "$done_marker"
  else
    echo "=== Task ${TASK_ID} ==="
    echo "Type:     $TASK_TYPE"
    echo "Desc:     $TASK_DESC"
    echo "CLI:      $ASSIGNED_CLI"
    echo "Mode:     $MODE"
    echo "Status:   $STATUS"
    echo "Depends:  ${DEPENDS_ON:-—}"
    echo "Output:   $OUTPUT_FILE"

    if [ "$output_exists" = "true" ]; then
      local size
      size=$(wc -c < "$abs_output" | tr -d ' ')
      echo "Output exists: ${size}B"
      if [ "$done_marker" = "true" ]; then
        echo "DONE marker: present"
      else
        echo "DONE marker: missing"
      fi
    else
      echo "Output: not yet created"
    fi
  fi
}

# ─── Pane Mapping ─────────────────────────────────────────────

# Register a CLI → pane_id mapping
pane_register() {
  local session_dir="$1" cli_name="$2" pane_id="$3"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  mkdir -p "$swarm_dir"
  local panes_file="$swarm_dir/panes.env"

  # Remove old entry for this CLI if exists
  if [ -f "$panes_file" ]; then
    grep -v "^PANE_${cli_name}=" "$panes_file" > "${panes_file}.tmp" 2>/dev/null || true
    mv "${panes_file}.tmp" "$panes_file"
  fi

  echo "PANE_${cli_name}=${pane_id}" >> "$panes_file"
}

# Auto-detect and register panes from tmux session
pane_auto_detect() {
  local session_dir="$1" tmux_session="$2"
  local tl_pane="${SWARM_TL_PANE:-}"
  local pane_list
  pane_list=$(tmux list-panes -t "$tmux_session" -F '#{pane_id}|#{pane_title}' 2>/dev/null)
  while IFS='|' read -r pid ptitle; do
    # Skip TL pane — dispatch to TL would interrupt its current conversation
    # Primary: match by persisted pane ID; fallback: title prefix
    if [ -n "$tl_pane" ] && [ "$pid" = "$tl_pane" ]; then
      continue
    fi
    echo "$ptitle" | grep -qi '^TL:' && continue
    for cli in claude gemini codex kimi; do
      if echo "$ptitle" | grep -qi "$cli"; then
        pane_register "$session_dir" "$cli" "$pid"
      fi
    done
  done <<< "$pane_list"
}

# Find pane for a CLI: check panes.env first, then fall back to title match
_find_pane_for_cli() {
  local session_dir="$1" cli_name="$2" tmux_session="$3"
  local tl_pane="${SWARM_TL_PANE:-}"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local panes_file="$swarm_dir/panes.env"

  # Try panes.env mapping first
  if [ -f "$panes_file" ]; then
    local mapped
    mapped=$(grep "^PANE_${cli_name}=" "$panes_file" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$mapped" ]; then
      # Skip if mapped pane is the TL pane (by ID or title)
      local skip_mapped=false
      if [ -n "$tl_pane" ] && [ "$mapped" = "$tl_pane" ]; then
        skip_mapped=true
      elif tmux list-panes -t "$tmux_session" -F '#{pane_id}|#{pane_title}' 2>/dev/null | grep -q "^${mapped}|TL:"; then
        skip_mapped=true
      fi
      if [ "$skip_mapped" = "false" ] && tmux list-panes -t "$tmux_session" -F '#{pane_id}' 2>/dev/null | grep -q "^${mapped}$"; then
        echo "$mapped"
        return 0
      fi
    fi
  fi

  # Fallback: match by pane title (skip TL pane by ID or title)
  local pane_list
  pane_list=$(tmux list-panes -t "$tmux_session" -F '#{pane_id}|#{pane_title}' 2>/dev/null)
  while IFS='|' read -r pid ptitle; do
    if [ -n "$tl_pane" ] && [ "$pid" = "$tl_pane" ]; then
      continue
    fi
    echo "$ptitle" | grep -qi '^TL:' && continue
    if echo "$ptitle" | grep -qi "$cli_name"; then
      echo "$pid"
      return 0
    fi
  done <<< "$pane_list"

  return 1
}

# ─── Self-Dispatch (TL assigns task to own CLI) ─────────────

_task_dispatch_self() {
  local session_dir="$1" task_id="$2" assigned_cli="$3"
  local tl_cli="${SWARM_TL_CLI:-}"

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"
  local prompt_path="${session_dir}/.swarm/prompts/${task_id}.md"
  local output_path="${session_dir}/.swarm/outputs/${task_id}.md"

  if [ "$tl_cli" = "claude" ]; then
    # Claude Code TL: output structured block for the calling session to parse
    # The TL's Claude Code session reads this from Bash stdout and spawns a Task subagent
    sed -i '' 's/^STATUS="[^"]*"/STATUS="active"/' "$task_file"
    cat <<EOF
SWARM_SELF_DISPATCH_START
TASK_ID=${task_id}
PROMPT_PATH=${prompt_path}
OUTPUT_PATH=${output_path}
SWARM_SELF_DISPATCH_END

[self-dispatch] 任务 ${task_id} 需要由 TL 自身执行。
请使用 Task subagent 阅读 ${prompt_path} 并将结果写到 ${output_path}
EOF
  else
    # Non-Claude TL: cannot self-dispatch, suggest reassignment
    echo "[self-dispatch] 错误: 任务 ${task_id} 分配给 ${assigned_cli}，但该 CLI 是 TL 自身。" >&2
    echo "[self-dispatch] TL (${tl_cli}) 无法向自己发送 tmux 指令。请重新分配到其他 CLI 或添加一个 ${assigned_cli} worker pane。" >&2
    return 1
  fi
}

# ─── Task Dispatch ────────────────────────────────────────────

task_dispatch() {
  local session_dir="$1" task_id="$2" tmux_session="$3"

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"

  if [ ! -f "$task_file" ]; then
    echo "任务 ${task_id} 不存在。" >&2
    return 1
  fi

  _task_source "$task_file"

  # Idempotent: skip if already active, done, or cancelled
  if [ "$STATUS" = "active" ]; then
    echo "[dispatch] 任务 ${task_id} 已在执行中，跳过。"
    return 0
  fi
  if [ "$STATUS" = "done" ]; then
    echo "[dispatch] 任务 ${task_id} 已完成，跳过。"
    return 0
  fi
  if [ "$STATUS" = "cancelled" ]; then
    echo "[dispatch] 任务 ${task_id} 已取消，跳过。"
    return 0
  fi

  # Check dependencies
  if ! _check_depends_done "$session_dir" "$DEPENDS_ON"; then
    echo "[dispatch] 任务 ${task_id} 有未完成的依赖 (${DEPENDS_ON})，跳过。"
    return 1
  fi

  # Self-dispatch guard: if task is assigned to the TL's own CLI, intercept
  local tl_cli="${SWARM_TL_CLI:-}"
  if [ -n "$tl_cli" ] && [ "$ASSIGNED_CLI" = "$tl_cli" ]; then
    # Check if there's a non-TL pane for this CLI
    local worker_pane=""
    worker_pane=$(_find_pane_for_cli "$session_dir" "$ASSIGNED_CLI" "$tmux_session") || true

    if [ -z "$worker_pane" ]; then
      # No worker pane available — warn and ask for confirmation
      echo "" >&2
      echo "[dispatch] ⚠️  警告：任务 ${task_id} 分配给 TL (${tl_cli})，这会打断当前操作。" >&2
      echo "[dispatch] （此确认仅在无 worker pane 时出现）" >&2
      echo "[dispatch]" >&2
      echo "[dispatch] 建议方案：" >&2
      echo "[dispatch]   1. 取消此任务：telos-swarm task cancel ${task_id}" >&2
      echo "[dispatch]   2. 在 Claude Code 中用 Task 工具执行子 agent" >&2
      echo "[dispatch]" >&2

      # Check if running in interactive terminal
      if [ ! -t 0 ]; then
        # Non-interactive environment: check environment variable
        if [ "${SWARM_FORCE_SELF_DISPATCH:-0}" = "1" ]; then
          echo "[dispatch] 非交互环境：SWARM_FORCE_SELF_DISPATCH=1，强制继续" >&2
        else
          echo "[dispatch] 非交互环境：默认拒绝 TL 自我分配" >&2
          echo "[dispatch] 提示：设置 SWARM_FORCE_SELF_DISPATCH=1 可强制继续" >&2
          return 1
        fi
      else
        # Interactive environment: ask for confirmation
        echo -n "[dispatch] 是否继续分发到 TL？(y/N) " >&2
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
          echo "[dispatch] 已取消分发任务 ${task_id}" >&2
          return 1
        fi
      fi

      # User confirmed or forced — use self-dispatch
      _task_dispatch_self "$session_dir" "$task_id" "$ASSIGNED_CLI"
      return $?
    else
      # Worker pane exists, but still warn about semantic inconsistency
      echo "" >&2
      echo "[dispatch] ⚠️  注意：任务 ${task_id} 名义上分配给 TL (${tl_cli})，但将派发到 worker pane" >&2
      echo "[dispatch] 建议：明确使用 --assign ${ASSIGNED_CLI} 而非依赖 TL CLI 名称" >&2
      echo "" >&2
      # Continue to dispatch to worker pane (fall through)
    fi
  fi

  # Find the pane for this CLI
  local target_pane=""
  target_pane=$(_find_pane_for_cli "$session_dir" "$ASSIGNED_CLI" "$tmux_session") || true

  if [ -z "$target_pane" ]; then
    echo "[dispatch] 找不到 ${ASSIGNED_CLI} 对应的 tmux pane。" >&2
    return 1
  fi

  # Check pane readiness (skip for known CLI TUIs which have their own input handling)
  case "$ASSIGNED_CLI" in
    claude|gemini|codex|kimi)
      # CLI TUIs don't show shell prompts; they have their own ready indicators
      # Skip the shell prompt check for these
      ;;
    *)
      # For other CLIs (or future shell-based agents), check shell prompt
      local last_captured
      last_captured=$(tmux capture-pane -t "$target_pane" -p 2>/dev/null | grep -v '^$' | tail -1)
      if ! echo "$last_captured" | grep -qE '[\$#%>] *$'; then
        echo "[dispatch] 警告: pane ${target_pane} 可能不在 shell 提示符，仍尝试发送。"
      fi
      ;;
  esac

  # Send the task instruction — single message with absolute paths
  # CLI TUIs (Claude Code, Gemini) treat each Enter as a prompt submission,
  # so we must NOT send "cd" as a separate message.
  # First, clear any existing input in the pane
  tmux send-keys -t "$target_pane" Escape
  sleep 0.3
  local mode_hint=""
  [ "$MODE" = "team" ] && mode_hint=" (可用 Team spawn 子 agent)"
  local prompt_path="${session_dir}/.swarm/prompts/${task_id}.md"
  local output_path="${session_dir}/.swarm/outputs/${task_id}.md"
  local instruction="阅读 ${prompt_path} 中的任务说明，将结果写到 ${output_path}${mode_hint}"
  tmux send-keys -l -t "$target_pane" "$instruction"
  sleep 0.3
  tmux send-keys -t "$target_pane" Enter

  # Update status → active (works from pending or failed)
  sed -i '' 's/^STATUS="[^"]*"/STATUS="active"/' "$task_file"
  echo "[dispatch] 任务 ${task_id} 已分发给 ${ASSIGNED_CLI}。"
}

task_dispatch_ready() {
  local session_dir="$1" tmux_session="$2"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local dispatched=0

  _lock_acquire "$session_dir" || return 1
  trap '_lock_release "'"$session_dir"'"' RETURN INT TERM

  for f in "$swarm_dir/tasks"/*.env; do
    [ -f "$f" ] || continue
    _task_source "$f"
    if [ "$STATUS" = "pending" ]; then
      if _check_depends_done "$session_dir" "$DEPENDS_ON"; then
        task_dispatch "$session_dir" "$TASK_ID" "$tmux_session"
        dispatched=$((dispatched + 1))
      fi
    fi
  done

  if [ "$dispatched" -eq 0 ]; then
    echo "没有可分发的就绪任务。"
  else
    echo "已分发 ${dispatched} 个任务。"
  fi
}

# ─── Task Poll ────────────────────────────────────────────────

task_poll() {
  local session_dir="$1"
  local timeout="${2:-300}"
  shift 2 2>/dev/null || true
  local specific_ids=("$@")

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local tmux_session="${SWARM_SESSION:-}"
  local elapsed=0
  local _poll_lock_held=false

  # Trap ensures lock is released on any exit (set -e, signal, etc.)
  trap '[ "${_poll_lock_held:-false}" = "true" ] && _lock_release "$session_dir" || true' RETURN INT TERM

  echo "轮询任务状态 (timeout: ${timeout}s)..."

  while [ "$elapsed" -lt "$timeout" ]; do
    _lock_acquire "$session_dir" || { sleep 5; elapsed=$((elapsed + 5)); continue; }
    _poll_lock_held=true

    local all_done=true
    local active_count=0

    for f in "$swarm_dir/tasks"/*.env; do
      [ -f "$f" ] || continue
      _task_source "$f"

      # If specific IDs given, skip others
      if [ ${#specific_ids[@]} -gt 0 ]; then
        local match=false
        for sid in "${specific_ids[@]}"; do
          [ "$sid" = "$TASK_ID" ] && match=true
        done
        [ "$match" = "false" ] && continue
      fi

      # Skip done tasks
      [ "$STATUS" = "done" ] && continue

      # Skip pending tasks - they haven't started yet and shouldn't block polling
      # (dispatch will handle them when dependencies are met)
      [ "$STATUS" = "pending" ] && continue

      # Skip cancelled tasks
      [ "$STATUS" = "cancelled" ] && continue

      if [ "$STATUS" = "active" ]; then
        local abs_output
        abs_output=$(_resolve_output_path "$session_dir" "$OUTPUT_FILE")
        if [ -f "$abs_output" ]; then
          local size
          size=$(wc -c < "$abs_output" | tr -d ' ')
          local last_line
          last_line=$(tail -1 "$abs_output")

          if [ "$last_line" = "<!-- SWARM:DONE -->" ]; then
            # Quality gate check
            local quality_result
            quality_result=$(task_check_quality "$session_dir" "$TASK_ID")
            sed -i '' "s/^QUALITY=\"[^\"]*\"/QUALITY=\"${quality_result}\"/" "$f"

            if [[ "$quality_result" == fail:* ]]; then
              sed -i '' 's/^STATUS="active"/STATUS="failed"/' "$f"
              echo "  ✗ 任务 ${TASK_ID} (${ASSIGNED_CLI}) 质量检查失败: ${quality_result#fail:}"
              hooks_fire "task_complete" "SWARM_TASK_ID=$TASK_ID" "SWARM_TASK_STATUS=failed" "SWARM_TASK_QUALITY=$quality_result" "SWARM_TASK_CLI=$ASSIGNED_CLI"
              if [ -n "$tmux_session" ]; then
                task_failover "$session_dir" "$TASK_ID" "$tmux_session"
              fi
            else
              sed -i '' 's/^STATUS="active"/STATUS="done"/' "$f"
              echo "  ✓ 任务 ${TASK_ID} (${ASSIGNED_CLI}) 完成 [quality: ${quality_result}]"
              hooks_fire "task_complete" "SWARM_TASK_ID=$TASK_ID" "SWARM_TASK_STATUS=done" "SWARM_TASK_QUALITY=$quality_result" "SWARM_TASK_CLI=$ASSIGNED_CLI"
            fi
          else
            # Check for stale (60s no write)
            local file_mtime
            file_mtime=$(stat -f %m "$abs_output" 2>/dev/null || stat -c %Y "$abs_output" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            if [ $((now - file_mtime)) -gt 60 ] && [ "$size" -gt 0 ]; then
              sed -i '' 's/^STATUS="active"/STATUS="failed"/' "$f"
              echo "  ✗ 任务 ${TASK_ID} (${ASSIGNED_CLI}) 超时标记为 failed（有产出但缺 DONE 标记且 60s 无写入）"

              # Attempt failover if Claude pane exists
              if [ -n "$tmux_session" ]; then
                task_failover "$session_dir" "$TASK_ID" "$tmux_session"
              fi
            else
              all_done=false
              active_count=$((active_count + 1))
            fi
          fi
        else
          all_done=false
          active_count=$((active_count + 1))
        fi
      fi

      [ "$STATUS" = "failed" ] && continue
    done

    # Check if we should auto-dispatch or are fully done
    if [ "$active_count" -eq 0 ]; then
      if [ -n "$tmux_session" ]; then
        # No active tasks — check for pending dependents to dispatch
        local has_dispatchable=false
        for f in "$swarm_dir/tasks"/*.env; do
          [ -f "$f" ] || continue
          local s deps
          s=$(_task_read_field "$f" "STATUS")
          deps=$(_task_read_field "$f" "DEPENDS_ON")
          if [ "$s" = "pending" ]; then
            if [ -z "$deps" ] || _check_depends_done "$session_dir" "$deps"; then
              # When filtering by specific_ids, only dispatch if depends on one of them
              if [ ${#specific_ids[@]} -gt 0 ]; then
                local is_downstream=false
                local IFS=','
                for dep in $deps; do
                  dep=$(echo "$dep" | tr -d ' ')
                  for sid in "${specific_ids[@]}"; do
                    [ "$dep" = "$sid" ] && is_downstream=true
                  done
                done
                unset IFS
                [ "$is_downstream" = "false" ] && continue
              fi
              has_dispatchable=true
              break
            fi
          fi
        done

        if [ "$has_dispatchable" = "true" ]; then
          echo ""
          echo "当前批次完成，推进依赖链..."
          _lock_release "$session_dir"; _poll_lock_held=false
          task_dispatch_ready "$session_dir" "$tmux_session"
          sleep 5
          elapsed=$((elapsed + 5))
          continue
        fi

        # No dispatchable tasks — check if truly all done
        if [ "$all_done" = "true" ]; then
          echo ""
          echo "所有任务已完成！"
          return 0
        fi

        # Pending tasks exist but deps not met yet (and no tmux to dispatch)
        echo ""
        echo "所有活跃任务完成，但有待处理任务无法自动分发。"
        echo "请手动运行: telos-swarm task dispatch"
        return 0
      fi

      if [ "$all_done" = "true" ]; then
        echo ""
        echo "所有任务已完成！"
        return 0
      fi

      # No tmux session — can't auto-dispatch
      echo ""
      echo "所有活跃任务完成，但有待处理任务无法自动分发。"
      echo "请手动运行: telos-swarm task dispatch"
      return 0
    fi

    _lock_release "$session_dir"; _poll_lock_held=false
    echo "  ... ${active_count} 个任务进行中 (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
  done

  # Trap handles lock release on return
  echo ""
  echo "超时！以下任务未完成："
  for f in "$swarm_dir/tasks"/*.env; do
    [ -f "$f" ] || continue
    _task_source "$f"
    if [ "$STATUS" = "active" ]; then
      echo "  - ${TASK_ID} (${ASSIGNED_CLI}): ${TASK_DESC}"
    fi
  done
  return 1
}

task_status() {
  local session_dir="$1"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")

  # ANSI colors
  local C_RESET='\033[0m'
  local C_BOLD='\033[1m'
  local C_GRAY='\033[90m'
  local C_YELLOW='\033[33m'
  local C_GREEN='\033[32m'
  local C_RED='\033[31m'
  local C_CYAN='\033[36m'

  echo -e "${C_BOLD}=== Task Status ===${C_RESET}"
  echo -e "${C_GRAY}Session: $session_dir${C_RESET}"
  echo ""

  if [ ! -d "$swarm_dir/tasks" ] || [ -z "$(ls "$swarm_dir/tasks/"*.env 2>/dev/null)" ]; then
    echo "没有任务。"
    return 0
  fi

  # Header
  printf "${C_BOLD}%-5s %-10s %-8s %-10s %-10s %-8s %s${C_RESET}\n" "ID" "TYPE" "CLI" "STATUS" "QUALITY" "TIME" "DESC"
  printf "%-5s %-10s %-8s %-10s %-10s %-8s %s\n" "---" "----" "---" "------" "-------" "----" "----"

  local total=0 pending=0 active=0 done_count=0 failed=0 cancelled=0
  local now
  now=$(date +%s)

  shopt -s nullglob
  for f in "$swarm_dir/tasks"/*.env; do
    [ -f "$f" ] || continue
    _task_source "$f"
    local quality
    quality=$(_task_read_field "$f" "QUALITY")
    local created_at
    created_at=$(_task_read_field "$f" "CREATED_AT")

    total=$((total + 1))

    # Calculate elapsed time
    local elapsed_str="—"
    if [ -n "$created_at" ] && [ "$created_at" -gt 0 ] 2>/dev/null; then
      local elapsed=$((now - created_at))
      if [ "$elapsed" -lt 60 ]; then
        elapsed_str="${elapsed}s"
      elif [ "$elapsed" -lt 3600 ]; then
        elapsed_str="$((elapsed / 60))m"
      else
        elapsed_str="$((elapsed / 3600))h$((elapsed % 3600 / 60))m"
      fi
    fi

    # Status color
    local status_colored="$STATUS"
    case "$STATUS" in
      pending)   status_colored="${C_GRAY}pending${C_RESET}"; pending=$((pending + 1)) ;;
      active)    status_colored="${C_YELLOW}active${C_RESET}"; active=$((active + 1)) ;;
      done)      status_colored="${C_GREEN}done${C_RESET}"; done_count=$((done_count + 1)) ;;
      failed)    status_colored="${C_RED}failed${C_RESET}"; failed=$((failed + 1)) ;;
      cancelled) status_colored="${C_GRAY}cancel${C_RESET}"; cancelled=$((cancelled + 1)) ;;
    esac

    # Quality color
    local quality_colored="${quality:-—}"
    case "${quality:-}" in
      pass)    quality_colored="${C_GREEN}pass${C_RESET}" ;;
      fail:*)  quality_colored="${C_RED}${quality}${C_RESET}" ;;
      pending) quality_colored="${C_GRAY}pending${C_RESET}" ;;
    esac

    # Truncate description
    local short_desc="${TASK_DESC:0:40}"
    [ ${#TASK_DESC} -gt 40 ] && short_desc="${short_desc}..."

    printf "%-5s %-10s %-8s " "$TASK_ID" "$TASK_TYPE" "$ASSIGNED_CLI"
    printf "%-10b %-10b %-8s %s\n" "$status_colored" "$quality_colored" "$elapsed_str" "$short_desc"
  done
  shopt -u nullglob

  # Progress bar (exclude cancelled from total)
  echo ""
  local effective_total=$((total - cancelled))
  local bar_width=40
  local done_w=0 active_w=0 failed_w=0 pending_w=0
  if [ "$effective_total" -gt 0 ]; then
    done_w=$((done_count * bar_width / effective_total))
    active_w=$((active * bar_width / effective_total))
    failed_w=$((failed * bar_width / effective_total))
    pending_w=$((bar_width - done_w - active_w - failed_w))
  fi

  printf "  ["
  printf "${C_GREEN}%0.s█${C_RESET}" $(seq 1 $done_w 2>/dev/null) || true
  printf "${C_YELLOW}%0.s█${C_RESET}" $(seq 1 $active_w 2>/dev/null) || true
  printf "${C_RED}%0.s█${C_RESET}" $(seq 1 $failed_w 2>/dev/null) || true
  printf "${C_GRAY}%0.s░${C_RESET}" $(seq 1 $pending_w 2>/dev/null) || true
  printf "] "
  echo -e "${C_GREEN}${done_count}${C_RESET}/${effective_total} done"

  echo -e "  ${C_GRAY}Pending: ${pending}${C_RESET} | ${C_YELLOW}Active: ${active}${C_RESET} | ${C_GREEN}Done: ${done_count}${C_RESET} | ${C_RED}Failed: ${failed}${C_RESET}${cancelled:+ | ${C_GRAY}Cancelled: ${cancelled}${C_RESET}}"
}

# ─── Task Retry ───────────────────────────────────────────────

task_retry() {
  local session_dir="$1" task_id="$2" tmux_session="$3"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"

  if [ ! -f "$task_file" ]; then
    echo "任务 ${task_id} 不存在。" >&2
    return 1
  fi

  # Reset to pending
  sed -i '' 's/^STATUS="[^"]*"/STATUS="pending"/' "$task_file"
  echo "任务 ${task_id} 已重置为 pending。"

  # Dispatch
  task_dispatch "$session_dir" "$task_id" "$tmux_session"
}

# ─── Task Cancel ─────────────────────────────────────────────

task_cancel() {
  local session_dir="$1" task_id="$2"
  local force=false
  [ "${3:-}" = "--force" ] && force=true

  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")

  _lock_acquire "$session_dir" || return 1
  trap '_lock_release "'"$session_dir"'"' RETURN INT TERM

  # Batch cancel all
  if [ "$task_id" = "all" ]; then
    local count=0
    for f in "$swarm_dir/tasks"/*.env; do
      [ -f "$f" ] || continue
      local s
      s=$(_task_read_field "$f" "STATUS")
      if [ "$s" = "pending" ]; then
        sed -i '' 's/^STATUS="[^"]*"/STATUS="cancelled"/' "$f"
        count=$((count + 1))
      elif [ "$s" = "active" ] && [ "$force" = "true" ]; then
        sed -i '' 's/^STATUS="[^"]*"/STATUS="cancelled"/' "$f"
        count=$((count + 1))
      fi
    done
    echo "已取消 ${count} 个任务。"
    [ "$force" = "true" ] && [ "$count" -gt 0 ] && echo "提示: 已取消的 active 任务，请检查对应 Pane 是否需要手动停止。"
    return 0
  fi

  local task_file="$swarm_dir/tasks/${task_id}.env"
  if [ ! -f "$task_file" ]; then
    echo "任务 ${task_id} 不存在。" >&2
    return 1
  fi

  local cur_status
  cur_status=$(_task_read_field "$task_file" "STATUS")

  if [ "$cur_status" = "done" ] || [ "$cur_status" = "cancelled" ]; then
    echo "任务 ${task_id} 状态为 ${cur_status}，无需取消。"
    return 0
  fi

  if [ "$cur_status" = "active" ] && [ "$force" != "true" ]; then
    echo "任务 ${task_id} 正在执行中，使用 --force 强制取消。" >&2
    return 1
  fi

  sed -i '' 's/^STATUS="[^"]*"/STATUS="cancelled"/' "$task_file"
  echo "任务 ${task_id} 已取消。"
  [ "$cur_status" = "active" ] && echo "提示: 请检查对应 Pane 是否需要手动停止。"

  # Warn about downstream tasks that depend on this one
  for f in "$swarm_dir/tasks"/*.env; do
    [ -f "$f" ] || continue
    local deps
    deps=$(_task_read_field "$f" "DEPENDS_ON")
    if echo ",$deps," | grep -q ",${task_id},"; then
      local downstream_id
      downstream_id=$(_task_read_field "$f" "TASK_ID")
      echo "  注意: 任务 ${downstream_id} 依赖 ${task_id}（cancelled 不阻塞下游 dispatch）"
    fi
  done
  return 0
}

# ─── Failover ─────────────────────────────────────────────────

task_failover() {
  local session_dir="$1" task_id="$2" tmux_session="$3"
  local swarm_dir
  swarm_dir=$(_swarm_dir "$session_dir")
  local task_file="$swarm_dir/tasks/${task_id}.env"

  _task_source "$task_file"

  # Find a Claude pane (that is NOT the TL pane)
  local claude_pane=""
  claude_pane=$(_find_pane_for_cli "$session_dir" "claude" "$tmux_session") || true

  if [ -z "$claude_pane" ]; then
    # No non-TL Claude pane — try self-dispatch if TL is Claude
    local tl_cli="${SWARM_TL_CLI:-}"
    if [ "$tl_cli" = "claude" ]; then
      echo "[failover] 没有独立 Claude worker pane，使用 TL 自身执行 failover。"
      sed -i '' 's/^ASSIGNED_CLI="[^"]*"/ASSIGNED_CLI="claude"/' "$task_file"
      sed -i '' 's/^STATUS="[^"]*"/STATUS="pending"/' "$task_file"
      _task_dispatch_self "$session_dir" "$task_id" "claude"
      return $?
    fi
    echo "[failover] 没有 Claude pane 可用。请手动使用: telos-swarm task retry ${task_id}" >&2
    return 1
  fi

  # Generate failover prompt
  local failover_prompt="$swarm_dir/prompts/${task_id}-failover.md"
  local existing_output
  existing_output=$(_resolve_output_path "$session_dir" "$OUTPUT_FILE")
  local progress=""
  [ -f "$existing_output" ] && progress=$(cat "$existing_output")

  cat > "$failover_prompt" <<EOF
## Failover Task

Original task (${task_id}) failed. Please take over.

### Original Description

${TASK_DESC}

### Existing Progress

${progress:-No previous output.}

### Instructions

Continue and complete this task. Write the final result to \`${OUTPUT_FILE}\`

CRITICAL: You MUST append \`<!-- SWARM:DONE -->\` as the very last line of your output file.
EOF

  # Send to Claude pane — single message with absolute path
  local failover_abs_path="${session_dir}/.swarm/prompts/${task_id}-failover.md"
  tmux send-keys -l -t "$claude_pane" "用 Team spawn 子 agent 接管任务，详见 ${failover_abs_path}"
  sleep 0.3
  tmux send-keys -t "$claude_pane" Enter

  # Update task
  sed -i '' 's/^ASSIGNED_CLI="[^"]*"/ASSIGNED_CLI="claude"/' "$task_file"
  sed -i '' 's/^MODE="[^"]*"/MODE="team"/' "$task_file"
  sed -i '' 's/^STATUS="[^"]*"/STATUS="active"/' "$task_file"

  echo "[failover] 任务 ${task_id} 已交给 Claude 接管。"
}
