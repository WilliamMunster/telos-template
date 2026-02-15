#!/bin/bash
# telos setup.sh — Interactive onboarding script for telos vault
# Usage: bash setup.sh [--non-interactive] [--help]
set -euo pipefail

# ─── Colors and symbols ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; }
info() { echo -e "${BLUE}🔧 $*${NC}"; }
step() { echo -e "\n${CYAN}${BOLD}$*${NC}"; }

# ─── Globals ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NON_INTERACTIVE=false
PLATFORM=""
INSTALLED_CLIS=""

# User config (defaults)
USER_NAME="${USER_NAME:-User}"
ROLE="${ROLE:-Developer}"
LANGUAGE="${LANGUAGE:-zh}"
VAULT_PATH="${VAULT_PATH:-$HOME/Documents/Obsidian Vault}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/project}"
SUPPORTED_CLIS=""

# Identity onboarding (Phase 2) defaults — empty means "keep placeholder"
CURRENT_POSITION=""
SHORT_TERM_GOAL=""
MID_TERM_GOAL=""
CORE_SKILLS=""       # comma-separated, max 3
MISSION_STATEMENT=""
CURRENT_CHALLENGE=""
# Projects collected as arrays
declare -a PROJECT_NAMES=()
declare -a PROJECT_STACKS=()
declare -a PROJECT_DESCS=()

# ─── Help ─────────────────────────────────────────────────────────────
show_help() {
  cat << 'EOF'
telos setup.sh — Initialize your personal AI infrastructure

Usage:
  bash setup.sh                  Interactive setup (recommended)
  bash setup.sh --non-interactive  Use defaults or environment variables
  bash setup.sh --help             Show this help

Environment variables (for --non-interactive mode):
  USER_NAME     Your name (default: "User")
  ROLE          Your role/profession (default: "Developer")
  LANGUAGE      Primary language: zh/en/ja (default: "zh")
  VAULT_PATH    Vault directory (default: ~/Documents/Obsidian Vault)
  PROJECT_DIR   Project directory (default: ~/project)
EOF
  exit 0
}

# ─── Step 1: detect_platform ──────────────────────────────────────────
detect_platform() {
  step "[环境检测] 检测操作系统..."
  case "$(uname -s)" in
    Darwin) PLATFORM="macos"; ok "macOS (Darwin)" ;;
    Linux)  PLATFORM="linux"; ok "Linux" ;;
    *)      PLATFORM="unknown"; warn "未知平台: $(uname -s)，将使用 Linux 默认值" ;;
  esac
}

# ─── Step 2: detect_installed_clis ───────────────────────────────────
detect_installed_clis() {
  step "[环境检测] 检测已安装的 AI CLI..."
  INSTALLED_CLIS=""

  if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
    INSTALLED_CLIS="$INSTALLED_CLIS claude"
    ok "Claude Code"
  fi
  if command -v gemini &>/dev/null || [ -d "$HOME/.gemini" ]; then
    INSTALLED_CLIS="$INSTALLED_CLIS gemini"
    ok "Gemini CLI"
  fi
  if command -v opencode &>/dev/null || [ -d "$HOME/.config/opencode" ]; then
    INSTALLED_CLIS="$INSTALLED_CLIS opencode"
    ok "opencode"
  fi
  if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
    INSTALLED_CLIS="$INSTALLED_CLIS codex"
    ok "Codex CLI"
  fi

  INSTALLED_CLIS="$(echo "$INSTALLED_CLIS" | xargs)"

  if [ -z "$INSTALLED_CLIS" ]; then
    warn "未检测到任何 AI CLI。你可以稍后安装："
    echo "  - Claude Code: npm install -g @anthropic-ai/claude-code"
    echo "  - Gemini CLI:  npm install -g @anthropic-ai/gemini-cli"
    echo "  - opencode:    go install github.com/opencode-ai/opencode@latest"
    INSTALLED_CLIS="claude"
    warn "默认启用 Claude Code 配置"
  fi

  SUPPORTED_CLIS="$INSTALLED_CLIS"
}

# ─── Step 3: run_onboarding ──────────────────────────────────────────
run_onboarding() {
  step "=== 欢迎使用 telos ==="
  echo "telos 是你的个人 AI 基础设施。让我们花 2 分钟完成初始设置。"
  echo ""

  # [1/6] Name
  echo -e "${BOLD}[1/6] 你叫什么名字？${NC}"
  read -r -p "> " input_name
  [ -n "$input_name" ] && USER_NAME="$input_name"
  ok "名字: $USER_NAME"
  echo ""

  # [2/6] Role
  echo -e "${BOLD}[2/6] 你的职业/角色是什么？（例：前端工程师、产品经理、学生）${NC}"
  read -r -p "> " input_role
  [ -n "$input_role" ] && ROLE="$input_role"
  ok "角色: $ROLE"
  echo ""

  # [3/6] Language
  echo -e "${BOLD}[3/6] 首选语言？${NC}"
  echo "  zh - 中文 (默认)"
  echo "  en - English"
  echo "  ja - 日本語"
  read -r -p "> " input_lang
  case "$input_lang" in
    en|EN) LANGUAGE="en" ;;
    ja|JA) LANGUAGE="ja" ;;
    *)     LANGUAGE="zh" ;;
  esac
  ok "语言: $LANGUAGE"
  echo ""

  # [4/6] Vault path
  echo -e "${BOLD}[4/6] Vault 路径？（默认: $HOME/Documents/Obsidian Vault）${NC}"
  read -r -p "> " input_vault
  [ -n "$input_vault" ] && VAULT_PATH="$input_vault"
  ok "Vault: $VAULT_PATH"
  echo ""

  # [5/6] Project directory
  echo -e "${BOLD}[5/6] 项目目录？（默认: $HOME/project）${NC}"
  read -r -p "> " input_project
  [ -n "$input_project" ] && PROJECT_DIR="$input_project"
  ok "项目目录: $PROJECT_DIR"
  echo ""

  # [6/6] Confirm CLIs
  echo -e "${BOLD}[6/6] 确认要配置的 AI CLI：${NC}"
  echo "  检测到: $INSTALLED_CLIS"
  echo "  直接回车确认，或输入你想配置的 CLI（空格分隔）："
  read -r -p "> " input_clis
  [ -n "$input_clis" ] && SUPPORTED_CLIS="$input_clis"
  ok "CLI: $SUPPORTED_CLIS"
}

# ─── Step 3b: run_identity_onboarding (Phase 2) ─────────────────────
run_identity_onboarding() {
  step "=== 身份定义（阶段二） ==="
  echo "接下来完善你的身份信息，每步都可以直接回车跳过。"
  echo ""

  # [1] Current position
  echo -e "${BOLD}[1/7] 当前职位/公司？（例：高级工程师 @ Google）${NC}"
  read -r -p "> " input
  [ -n "$input" ] && CURRENT_POSITION="$input"
  if [ -n "$CURRENT_POSITION" ]; then
    ok "职位: $CURRENT_POSITION"
  else
    info "跳过"
  fi
  echo ""

  # [2] Short-term goal
  echo -e "${BOLD}[2/7] 短期目标？（3-6 个月内想达成的）${NC}"
  read -r -p "> " input
  [ -n "$input" ] && SHORT_TERM_GOAL="$input"
  if [ -n "$SHORT_TERM_GOAL" ]; then
    ok "短期目标: $SHORT_TERM_GOAL"
  else
    info "跳过"
  fi
  echo ""

  # [3] Mid-term goal
  echo -e "${BOLD}[3/7] 中期目标？（1-2 年内想达成的）${NC}"
  read -r -p "> " input
  [ -n "$input" ] && MID_TERM_GOAL="$input"
  if [ -n "$MID_TERM_GOAL" ]; then
    ok "中期目标: $MID_TERM_GOAL"
  else
    info "跳过"
  fi
  echo ""

  # [4] Core skills
  echo -e "${BOLD}[4/7] 核心能力？（逗号分隔，最多 3 个，例：后端开发,系统设计,团队管理）${NC}"
  read -r -p "> " input
  [ -n "$input" ] && CORE_SKILLS="$input"
  if [ -n "$CORE_SKILLS" ]; then
    ok "核心能力: $CORE_SKILLS"
  else
    info "跳过"
  fi
  echo ""

  # [5] Mission
  echo -e "${BOLD}[5/7] 使命（一句话描述你想通过工作实现什么）${NC}"
  read -r -p "> " input
  [ -n "$input" ] && MISSION_STATEMENT="$input"
  if [ -n "$MISSION_STATEMENT" ]; then
    ok "使命: $MISSION_STATEMENT"
  else
    info "跳过"
  fi
  echo ""

  # [6] Current challenge
  echo -e "${BOLD}[6/7] 当前最大的挑战是什么？${NC}"
  read -r -p "> " input
  [ -n "$input" ] && CURRENT_CHALLENGE="$input"
  if [ -n "$CURRENT_CHALLENGE" ]; then
    ok "挑战: $CURRENT_CHALLENGE"
  else
    info "跳过"
  fi
  echo ""

  # [7] Projects (multi-entry)
  echo -e "${BOLD}[7/7] 当前项目（可输入多个，空行结束）${NC}"
  echo "  格式：项目名 / 技术栈 / 说明"
  echo "  例：my-app / React + Node / 个人博客"
  echo ""
  while true; do
    read -r -p "  > " input
    [ -z "$input" ] && break
    # Parse: name / stack / desc
    local p_name p_stack p_desc
    p_name="$(echo "$input" | cut -d'/' -f1 | xargs)"
    p_stack="$(echo "$input" | cut -d'/' -f2 | xargs 2>/dev/null)"
    p_desc="$(echo "$input" | cut -d'/' -f3- | xargs 2>/dev/null)"
    [ -z "$p_name" ] && continue
    PROJECT_NAMES+=("$p_name")
    PROJECT_STACKS+=("${p_stack:-}")
    PROJECT_DESCS+=("${p_desc:-}")
    ok "  项目: $p_name"
  done
  if [ ${#PROJECT_NAMES[@]} -eq 0 ]; then
    info "跳过项目"
  fi
  echo ""

  # Print summary
  step "=== 身份信息摘要 ==="
  [ -n "$CURRENT_POSITION" ] && echo "  职位:     $CURRENT_POSITION"
  [ -n "$SHORT_TERM_GOAL" ]  && echo "  短期目标: $SHORT_TERM_GOAL"
  [ -n "$MID_TERM_GOAL" ]    && echo "  中期目标: $MID_TERM_GOAL"
  [ -n "$CORE_SKILLS" ]      && echo "  核心能力: $CORE_SKILLS"
  [ -n "$MISSION_STATEMENT" ] && echo "  使命:     $MISSION_STATEMENT"
  [ -n "$CURRENT_CHALLENGE" ] && echo "  挑战:     $CURRENT_CHALLENGE"
  if [ ${#PROJECT_NAMES[@]} -gt 0 ]; then
    echo "  项目:"
    for i in "${!PROJECT_NAMES[@]}"; do
      echo "    - ${PROJECT_NAMES[$i]}"
    done
  fi
  echo ""
  ok "身份信息收集完成"
}

# ─── Step 4: create_directories ──────────────────────────────────────
create_directories() {
  step "[目录结构] 创建 vault 目录..."

  local dirs=(
    "_telos"
    "_agents/instructions"
    "_agents/commands"
    "_agents/hooks/adapters/claude"
    "_agents/hooks/adapters/gemini"
    "_agents/hooks/adapters/opencode"
    "_agents/hooks/lib"
    "_agents/skills"
    "_journal/daily"
    "_journal/weekly"
    "work/personal"
    "work/company"
    "knowledge"
    "attachments"
  )

  for dir in "${dirs[@]}"; do
    mkdir -p "$SCRIPT_DIR/$dir"
  done

  # Add .gitkeep to empty leaf directories
  local gitkeep_dirs=(
    "_agents/skills"
    "_journal/daily"
    "_journal/weekly"
    "work/personal"
    "work/company"
    "knowledge"
    "attachments"
  )

  for dir in "${gitkeep_dirs[@]}"; do
    local target="$SCRIPT_DIR/$dir/.gitkeep"
    [ -f "$target" ] || touch "$target"
  done

  ok "目录结构创建完成"
}

# ─── Step 5: generate_telos_files ────────────────────────────────────
generate_telos_files() {
  step "[身份系统] 生成 _telos/ 模板文件..."

  local telos_dir="$SCRIPT_DIR/_telos"
  local today
  today="$(date +%Y-%m-%d)"

  # Phase 1: basic variable substitution
  for f in "$telos_dir"/*.md; do
    [ -f "$f" ] || continue

    # Date placeholders
    sed -i.bak \
      -e "s/{{DATE}}/$today/g" \
      -e "s/{{YEAR}}/$(date +%Y)/g" \
      -e "s/{{MONTH}}/$(date +%m)/g" \
      "$f"
    rm -f "$f.bak"

    # Basic identity
    if grep -q '\[你的名字\]' "$f" 2>/dev/null; then
      sed -i.bak "s/\[你的名字\]/$USER_NAME/g" "$f"
      rm -f "$f.bak"
    fi
    if grep -q '\[你的职业\]' "$f" 2>/dev/null; then
      sed -i.bak "s/\[你的职业\]/$ROLE/g" "$f"
      rm -f "$f.bak"
    fi
    if grep -q '\[你的领域\]' "$f" 2>/dev/null; then
      sed -i.bak "s/\[你的领域\]/$ROLE/g" "$f"
      rm -f "$f.bak"
    fi
  done

  # Phase 2: identity onboarding substitution (only if values were collected)
  if [ -n "$CURRENT_POSITION" ]; then
    sed -i.bak "s|\[你的当前职位/公司\]|$CURRENT_POSITION|g" "$telos_dir/identity.md"
    rm -f "$telos_dir/identity.md.bak"
  fi

  if [ -n "$SHORT_TERM_GOAL" ]; then
    sed -i.bak "s|\[你的短期目标\]|$SHORT_TERM_GOAL|g" "$telos_dir/identity.md"
    rm -f "$telos_dir/identity.md.bak"
    # Also update goals.md O1
    sed -i.bak "s|\[你的第一个目标\]|$SHORT_TERM_GOAL|g" "$telos_dir/goals.md"
    rm -f "$telos_dir/goals.md.bak"
  fi

  if [ -n "$MID_TERM_GOAL" ]; then
    sed -i.bak "s|\[你的中期目标\]|$MID_TERM_GOAL|g" "$telos_dir/identity.md"
    rm -f "$telos_dir/identity.md.bak"
    # Also update goals.md O2
    sed -i.bak "s|\[你的第二个目标\]|$MID_TERM_GOAL|g" "$telos_dir/goals.md"
    rm -f "$telos_dir/goals.md.bak"
  fi

  # Core skills → identity.md capability table
  if [ -n "$CORE_SKILLS" ]; then
    local IFS_OLD="$IFS"
    IFS=',' read -ra skills <<< "$CORE_SKILLS"
    IFS="$IFS_OLD"
    local idx=1
    for skill in "${skills[@]}"; do
      skill="$(echo "$skill" | xargs)"  # trim whitespace
      [ -z "$skill" ] && continue
      if [ $idx -le 3 ]; then
        sed -i.bak "s|\[技能维度${idx}\]|$skill|g" "$telos_dir/identity.md"
        rm -f "$telos_dir/identity.md.bak"
        idx=$((idx + 1))
      fi
    done
  fi

  # Mission → mission.md
  if [ -n "$MISSION_STATEMENT" ]; then
    sed -i.bak "s|\[你的使命宣言\]|$MISSION_STATEMENT|g" "$telos_dir/mission.md"
    rm -f "$telos_dir/mission.md.bak"
  fi

  # Challenge → challenges.md
  if [ -n "$CURRENT_CHALLENGE" ]; then
    sed -i.bak "s|\[挑战标题\]|$CURRENT_CHALLENGE|g" "$telos_dir/challenges.md"
    rm -f "$telos_dir/challenges.md.bak"
    # Clear the description placeholder with a reasonable default
    sed -i.bak "s|\[挑战描述.*\]|待补充具体描述和应对策略|g" "$telos_dir/challenges.md"
    rm -f "$telos_dir/challenges.md.bak"
  fi

  # Projects → projects.md
  if [ ${#PROJECT_NAMES[@]} -gt 0 ]; then
    local first_name="${PROJECT_NAMES[0]}"
    local first_stack="${PROJECT_STACKS[0]:-}"
    local first_desc="${PROJECT_DESCS[0]:-}"
    # Use python for reliable replacement of the first placeholder project row
    python3 -c "
import re, sys
with open('$telos_dir/projects.md', 'r') as f:
    content = f.read()
# Replace the first personal project placeholder row
content = content.replace(
    '| **[项目名]** | ⬜ | [技术栈] | [说明] | [设备] |',
    '| **${first_name}** | ⬜ | ${first_stack} | ${first_desc} | all |',
    1
)
with open('$telos_dir/projects.md', 'w') as f:
    f.write(content)
"

    # Append additional projects after the telos row
    if [ ${#PROJECT_NAMES[@]} -gt 1 ]; then
      for i in $(seq 1 $((${#PROJECT_NAMES[@]} - 1))); do
        local pn="${PROJECT_NAMES[$i]}"
        local ps="${PROJECT_STACKS[$i]:-}"
        local pd="${PROJECT_DESCS[$i]:-}"
        sed -i.bak "/\*\*telos\*\*/a\\
| **${pn}** | ⬜ | ${ps} | ${pd} | all |" "$telos_dir/projects.md"
        rm -f "$telos_dir/projects.md.bak"
      done
    fi
  fi

  ok "_telos/ 文件变量替换完成"
}

# ─── Step 6: generate_agent_config ───────────────────────────────────
generate_agent_config() {
  step "[配置] 生成 _agents/config.env..."

  local config_file="$SCRIPT_DIR/_agents/config.env"

  cat > "$config_file" << ENVEOF
# _agents/config.env — telos user configuration
# Generated by setup.sh on $(date +%Y-%m-%d)
# You can edit this file manually.

# Basic info
USER_NAME="$USER_NAME"
ROLE="$ROLE"
LANGUAGE="$LANGUAGE"

# Paths
VAULT_PATH="$VAULT_PATH"
PROJECT_DIR="$PROJECT_DIR"

# Supported CLIs (space-separated)
SUPPORTED_CLIS="$SUPPORTED_CLIS"

# Obsidian CLI path (leave empty for auto-detection)
OBSIDIAN_PATH=""

# Platform (auto-detected)
PLATFORM="$PLATFORM"
ENVEOF

  ok "config.env 生成完成"
}

# ─── Step 7: generate_identity ────────────────────────────────────────
generate_identity() {
  step "[身份] 生成 _agents/identity.md..."

  local identity_file="$SCRIPT_DIR/_agents/identity.md"

  # If identity.md exists and has template variables, substitute them
  if [ -f "$identity_file" ]; then
    sed -i.bak \
      -e "s/{{USER_NAME}}/$USER_NAME/g" \
      -e "s/{{ROLE}}/$ROLE/g" \
      -e "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" \
      -e "s|{{VAULT_PATH}}|$VAULT_PATH|g" \
      "$identity_file"
    rm -f "$identity_file.bak"
    ok "identity.md 变量替换完成"
  else
    # Generate from scratch if not present
    cat > "$identity_file" << IDEOF
# TELOS — $USER_NAME's AI Identity

## Who I Am

$ROLE. I use telos to maintain persistent context across AI CLI sessions.

## Current Goals

(Edit _telos/goals.md to define your objectives)

## Decision Principles

(Edit _telos/beliefs.md to define your principles)

## Active Projects

(Edit _telos/projects.md to list your projects)

## Communication

- Language preference: $LANGUAGE
- Be direct, skip fluff
- When in doubt, check \`_telos/beliefs.md\`
IDEOF
    ok "identity.md 生成完成"
  fi
}

# ─── Step 8: setup_cli_symlinks ──────────────────────────────────────
setup_cli_symlinks() {
  step "[链接] 创建 CLI symlink..."

  local agents_dir="$SCRIPT_DIR/_agents"
  local link_target="$HOME/.agents"

  if [ -L "$link_target" ]; then
    local current_target
    current_target="$(readlink "$link_target")"
    if [ "$current_target" = "$agents_dir" ]; then
      ok "~/.agents 已指向正确目录"
      return
    fi
    # Existing symlink points elsewhere — ask before overwriting
    if [ "$NON_INTERACTIVE" = true ]; then
      warn "~/.agents 已指向 ${current_target}（非本 vault），非交互模式下跳过覆盖"
      return
    fi
    warn "~/.agents 当前指向 ${current_target}"
    printf "  是否更新为 ${agents_dir}? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      rm "$link_target"
    else
      info "保留现有 ~/.agents，跳过"
      return
    fi
  elif [ -e "$link_target" ]; then
    warn "~/.agents 已存在且不是 symlink，跳过"
    return
  fi

  ln -s "$agents_dir" "$link_target"
  ok "~/.agents -> $agents_dir"
}

# ─── Step 9: run_sync ─────────────────────────────────────────────────
run_sync() {
  step "[同步] 执行 sync.sh..."

  local sync_script="$SCRIPT_DIR/_agents/sync.sh"

  if [ -x "$sync_script" ]; then
    if bash "$sync_script" all; then
      ok "sync.sh all 执行完成"
    else
      warn "sync.sh all 执行出错，可稍后手动运行"
    fi
  else
    warn "sync.sh 不存在或不可执行，跳过同步"
  fi
}

# ─── Step 10: setup_claude_hooks ─────────────────────────────────────
setup_claude_hooks() {
  step "[Hooks] 配置 Claude Code hooks..."

  # Only configure if claude is in supported CLIs
  if ! echo "$SUPPORTED_CLIS" | grep -qw "claude"; then
    info "Claude Code 未在支持列表中，跳过 hooks 配置"
    return
  fi

  local claude_dir="$HOME/.claude"
  local settings_file="$claude_dir/settings.local.json"
  local hooks_dir="$SCRIPT_DIR/_agents/hooks/adapters/claude"

  mkdir -p "$claude_dir"

  # Check if python3 is available
  if ! command -v python3 &>/dev/null; then
    warn "python3 未安装，跳过 hooks 配置。请手动配置 $settings_file"
    return
  fi

  # Generate hooks JSON and merge with existing settings
  python3 << PYEOF
import json
import os

hooks_dir = "$hooks_dir"
settings_file = "$settings_file"

hooks_config = {
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Bash|Edit|Write|MultiEdit|Read",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/security-validator.sh"}]
            }
        ],
        "PostToolUse": [
            {
                "matcher": "Write|Edit",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/post-tool-tracker.sh"}]
            }
        ],
        "Notification": [
            {
                "matcher": "",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/notification-router.sh"}]
            }
        ],
        "PreCompact": [
            {
                "matcher": "",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/pre-compact.sh"}]
            }
        ],
        "Stop": [
            {
                "matcher": "",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/session-end.sh"}]
            }
        ],
        "SessionStart": [
            {
                "matcher": "",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/session-start.sh"}]
            }
        ],
        "UserPromptSubmit": [
            {
                "matcher": "",
                "hooks": [{"type": "command", "command": f"bash {hooks_dir}/prompt-context.sh"}]
            }
        ]
    }
}

# Merge with existing settings if present
existing = {}
if os.path.isfile(settings_file):
    try:
        with open(settings_file, "r") as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

existing.update(hooks_config)

with open(settings_file, "w") as f:
    json.dump(existing, f, indent=2)
PYEOF

  if [ $? -eq 0 ]; then
    ok "Claude Code hooks 配置完成: $settings_file"
  else
    warn "hooks 配置写入失败"
  fi
}

# ─── Step 11: setup_git ──────────────────────────────────────────────
setup_git() {
  step "[Git] 初始化版本控制..."

  cd "$SCRIPT_DIR"

  if [ ! -d ".git" ]; then
    git init -q
    ok "git init 完成"
  else
    ok "git 仓库已存在"
  fi

  git add -A
  if git diff --cached --quiet 2>/dev/null; then
    ok "没有新的变更需要提交"
  else
    git commit -q -m "feat: initialize telos vault"
    ok "初始提交完成"
  fi
}

# ─── Step 12: run_verify ─────────────────────────────────────────────
run_verify() {
  step "[验证] 检查 vault 健康状态..."

  local sync_script="$SCRIPT_DIR/_agents/sync.sh"

  if [ -x "$sync_script" ]; then
    if bash "$sync_script" verify; then
      ok "验证通过"
    else
      warn "部分检查未通过，请查看上方输出"
    fi
  else
    # Fallback: basic verification
    local errors=0

    # Check key directories
    for dir in _telos _agents _journal work knowledge; do
      if [ -d "$SCRIPT_DIR/$dir" ]; then
        ok "目录存在: $dir"
      else
        fail "目录缺失: $dir"
        errors=$((errors + 1))
      fi
    done

    # Check key files
    for f in _agents/config.env _agents/identity.md; do
      if [ -f "$SCRIPT_DIR/$f" ]; then
        ok "文件存在: $f"
      else
        fail "文件缺失: $f"
        errors=$((errors + 1))
      fi
    done

    # Check symlink
    if [ -L "$HOME/.agents" ]; then
      ok "symlink 存在: ~/.agents"
    else
      warn "symlink 缺失: ~/.agents"
    fi

    if [ "$errors" -eq 0 ]; then
      ok "基础验证通过"
    else
      warn "$errors 个问题需要关注"
    fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────
main() {
  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --non-interactive) NON_INTERACTIVE=true ;;
      --help|-h)        show_help ;;
      *)                warn "未知参数: $arg" ;;
    esac
  done

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       telos — AI Identity Setup      ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""

  # 1. Detect environment
  detect_platform
  detect_installed_clis

  # 2. Interactive onboarding (or use defaults)
  if [ "$NON_INTERACTIVE" = false ]; then
    run_onboarding

    # Phase 2: Identity onboarding (optional)
    echo ""
    echo -e "${BOLD}基础配置完成！是否继续完善身份信息？${NC}"
    echo "  身份信息会填充 _telos/ 下的模板文件，也可以稍后手动编辑。"
    read -r -p "继续？[Y/n] " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      run_identity_onboarding
    else
      info "跳过身份定义，你可以稍后编辑 _telos/ 文件"
    fi
  else
    info "非交互模式：使用默认值或环境变量"
    info "USER_NAME=$USER_NAME, ROLE=$ROLE, LANGUAGE=$LANGUAGE"
  fi

  # 3. Create directory structure
  create_directories

  # 4. Generate files from templates
  generate_telos_files
  generate_agent_config
  generate_identity

  # 5. Setup CLI integration
  setup_cli_symlinks
  run_sync

  # 6. Configure hooks (Claude Code only)
  setup_claude_hooks

  # 7. Initialize git
  setup_git

  # 8. Verify
  run_verify

  # Done
  echo ""
  echo -e "${GREEN}${BOLD}=== 设置完成！ ===${NC}"
  echo ""
  echo "下一步："
  echo "  1. 查看 _telos/ 下的文件，补充或调整你的身份信息"
  echo "  2. 启动你的 AI CLI（如 claude），上下文会自动加载"
  echo "  3. 试试 /daily-log 记录你的第一条日志"
  echo ""
  echo "随时运行 '_agents/sync.sh verify' 检查健康状态。"
}

main "$@"
