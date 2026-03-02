#!/usr/bin/env bash
# link-analyzer.sh - Obsidian vault 链接分析和优化工具
# 用途：分析孤立文件、建议链接、生成报告

set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$HOME/Documents/Obsidian Vault}"
cd "$VAULT_ROOT"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 使用说明
usage() {
  cat <<EOF
用法: $(basename "$0") [命令] [选项]

命令:
  scan              扫描所有孤立文件（无入链）
  analyze           分析孤立文件并分类
  suggest <file>    为指定文件建议链接位置
  report            生成完整分析报告
  check             快速健康检查

选项:
  --exclude-system  排除系统文件（commands/instructions/templates/backup）
  --json            以 JSON 格式输出
  --verbose         详细输出

示例:
  $(basename "$0") scan --exclude-system
  $(basename "$0") suggest "work/personal/telos/some-doc.md"
  $(basename "$0") report > link-report.md
EOF
  exit 1
}

# 检查文件是否是系统文件
is_system_file() {
  local file="$1"

  # 系统目录模式
  if echo "$file" | grep -qE "^\./_agents/(\.backup|commands|instructions|scripts/telos-swarm/templates)"; then
    return 0
  fi
  if echo "$file" | grep -qE "^\./_templates/|^\./_claude/"; then
    return 0
  fi
  if echo "$file" | grep -qE "^\./_agents/skills/.*/SKILL\.md$|^\./_agents/skills/.*/AGENTS\.md$"; then
    return 0
  fi

  return 1
}

# 扫描孤立文件
scan_orphans() {
  local exclude_system="${1:-false}"

  find . -name "*.md" -type f | while read -r file; do
    # 排除系统文件
    if [ "$exclude_system" = "true" ] && is_system_file "$file"; then
      continue
    fi

    basename_no_ext=$(basename "$file" .md)

    # 检查入链（包括带路径的链接）
    inlinks=$(grep -r "\[\[.*$basename_no_ext" . --include="*.md" 2>/dev/null | grep -v "^$file:" | wc -l | tr -d ' ')

    if [ "$inlinks" = "0" ]; then
      echo "$file"
    fi
  done
}

# 分析文件类型
analyze_file_type() {
  local file="$1"

  # 系统文件
  if is_system_file "$file"; then
    echo "system"
    return
  fi

  # TELOS 核心文件
  if echo "$file" | grep -qE "^\./_telos/"; then
    echo "telos"
    return
  fi

  # 工作文档
  if echo "$file" | grep -qE "^\./(work|docs)/"; then
    echo "work"
    return
  fi

  # 知识库
  if echo "$file" | grep -qE "^\./knowledge/"; then
    echo "knowledge"
    return
  fi

  # 日志
  if echo "$file" | grep -qE "^\./_journal/"; then
    echo "journal"
    return
  fi

  # 其他
  echo "other"
}

# 建议链接位置
suggest_links() {
  local file="$1"
  local type=$(analyze_file_type "$file")
  local basename_no_ext=$(basename "$file" .md)

  echo "文件: $file"
  echo "类型: $type"
  echo ""
  echo "建议链接位置:"

  case "$type" in
    telos)
      echo "  - 在 _telos/identity.md 或 _telos/goals.md 中引用"
      echo "  - 如果是策略文档，在 _telos/strategies.md 中引用"
      ;;
    work)
      echo "  - 在 _telos/worklog.md 的相关工作项中引用"
      echo "  - 在 _telos/projects.md 的相关项目中引用"
      echo "  - 创建或更新同目录的 README.md 索引"
      ;;
    knowledge)
      echo "  - 在 _telos/goals.md 的相关目标中引用"
      echo "  - 在使用该知识的工作文档中引用"
      ;;
    journal)
      echo "  - 日志文件通常不需要入链"
      echo "  - 如果是重要的会话摘要，在对应日期的 daily note 中引用"
      ;;
    system)
      echo "  - 系统文件不需要手动链接"
      ;;
    other)
      echo "  - 根据内容判断应该在哪里引用"
      echo "  - 考虑是否应该移动到更合适的目录"
      ;;
  esac

  echo ""
  echo "相关文件（可能需要建立链接）:"

  # 搜索内容相关的文件（通过关键词）
  if [ -f "$file" ]; then
    # 提取文件中的关键词（标题、标签）
    keywords=$(grep -E "^# |^tags:" "$file" 2>/dev/null | head -5 | sed 's/^# //; s/^tags://; s/  - //' | tr '\n' ' ')

    if [ -n "$keywords" ]; then
      echo "  基于关键词搜索: $keywords"
      for keyword in $keywords; do
        grep -l "$keyword" ./_telos/*.md 2>/dev/null | head -3 | sed 's/^/    - /'
      done
    fi
  fi
}

# 生成分析报告
generate_report() {
  local exclude_system="${1:-true}"

  cat <<EOF
# Obsidian Vault 链接分析报告

生成时间: $(date '+%Y-%m-%d %H:%M:%S')

## 概览

EOF

  local total_files=$(find . -name "*.md" -type f | wc -l | tr -d ' ')
  local orphan_files=$(scan_orphans "$exclude_system" | wc -l | tr -d ' ')

  echo "- 总文件数: $total_files"
  echo "- 孤立文件数: $orphan_files"

  # 计算覆盖率（避免 awk 语法问题）
  if [ "$total_files" -gt 0 ]; then
    local coverage=$(python3 -c "print(f'{(1 - $orphan_files / $total_files) * 100:.1f}%')" 2>/dev/null || echo "N/A")
    echo "- 链接覆盖率: $coverage"
  fi
  echo ""

  cat <<EOF

## 孤立文件分类

EOF

  # 按类型分类（不使用关联数组，改用简单分组）
  local current_type=""

  # 按类型分类（不使用关联数组，改用简单分组）
  local current_type=""

  scan_orphans "$exclude_system" | while read -r file; do
    type=$(analyze_file_type "$file")
    echo "$type|$file"
  done | sort | while IFS='|' read -r type file; do
    # 输出类型标题（只在类型变化时）
    if [ "$type" != "$current_type" ]; then
      current_type="$type"
      case "$type" in
        system) echo ""; echo "### 系统文件"; echo "" ;;
        telos) echo ""; echo "### TELOS 核心文件"; echo "" ;;
        work) echo ""; echo "### 工作文档"; echo "" ;;
        knowledge) echo ""; echo "### 知识库"; echo "" ;;
        journal) echo ""; echo "### 日志"; echo "" ;;
        other) echo ""; echo "### 其他"; echo "" ;;
      esac
    fi

    echo "- $file"
  done

  cat <<EOF

## 建议行动

EOF

  # 统计需要处理的文件
  local needs_action=$(scan_orphans "$exclude_system" | while read -r file; do
    type=$(analyze_file_type "$file")
    if [ "$type" != "system" ] && [ "$type" != "journal" ]; then
      echo "$file"
    fi
  done | wc -l | tr -d ' ')

  if [ "$needs_action" -eq 0 ]; then
    echo "✅ 无需处理，所有有意义的文件都已建立链接。"
  else
    echo "需要建立链接的文件: $needs_action 个"
    echo ""
    echo "使用以下命令查看具体建议:"
    echo '```bash'
    echo "bash _agents/scripts/link-analyzer.sh suggest <file>"
    echo '```'
  fi
}

# 快速健康检查
quick_check() {
  local total_files=$(find . -name "*.md" -type f | wc -l | tr -d ' ')
  local orphan_files=$(scan_orphans true | wc -l | tr -d ' ')

  # 计算覆盖率
  local coverage=$(python3 -c "print(f'{(1 - $orphan_files / $total_files) * 100:.1f}')" 2>/dev/null || echo "N/A")

  echo -e "${BLUE}=== Vault 链接健康检查 ===${NC}"
  echo ""
  echo "总文件数: $total_files"
  echo "孤立文件: $orphan_files (排除系统文件)"
  echo -e "链接覆盖率: ${GREEN}${coverage}%${NC}"
  echo ""

  if [ "$orphan_files" -eq 0 ]; then
    echo -e "${GREEN}✅ 健康状况：优秀${NC}"
    echo "所有有意义的文件都已建立链接。"
  elif [ "$orphan_files" -lt 10 ]; then
    echo -e "${GREEN}✅ 健康状况：良好${NC}"
    echo "少量文件需要建立链接。"
  elif [ "$orphan_files" -lt 30 ]; then
    echo -e "${YELLOW}⚠️  健康状况：一般${NC}"
    echo "建议优化链接结构。"
  else
    echo -e "${RED}❌ 健康状况：需要改进${NC}"
    echo "大量文件缺少链接，建议执行链接优化。"
  fi

  echo ""
  echo "运行 'bash _agents/scripts/link-analyzer.sh report' 查看详细报告"
}

# 主函数
main() {
  local command="${1:-}"
  shift || true

  local exclude_system=false
  local json_output=false
  local verbose=false

  # 解析选项
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --exclude-system)
        exclude_system=true
        shift
        ;;
      --json)
        json_output=true
        shift
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  case "$command" in
    scan)
      scan_orphans "$exclude_system"
      ;;
    analyze)
      scan_orphans "$exclude_system" | while read -r file; do
        type=$(analyze_file_type "$file")
        echo "$type|$file"
      done | sort
      ;;
    suggest)
      if [ $# -eq 0 ]; then
        echo "错误: 需要指定文件路径" >&2
        usage
      fi
      suggest_links "$1"
      ;;
    report)
      generate_report "$exclude_system"
      ;;
    check)
      quick_check
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
