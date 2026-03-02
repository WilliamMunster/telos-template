#!/usr/bin/env bash
set -euo pipefail

# journal-link.sh - 建立 daily/weekly/monthly 三层时间关联体系
# 用法: bash journal-link.sh [--dry-run]

VAULT="${VAULT:-$HOME/Documents/Obsidian Vault}"
DAILY_DIR="$VAULT/_journal/daily"
WEEKLY_DIR="$VAULT/_journal/weekly"
MONTHLY_DIR="$VAULT/_journal/monthly"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# 压缩连续空行（最多保留 1 个）
squeeze_blank_lines() {
  local file="$1"
  awk '
    /^$/ { if (!blank) { print; blank=1 }; next }
    { blank=0; print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# 获取周一日期（给定日期所在周的周一）
get_monday() {
  local date="$1"
  # macOS: 计算当前是周几，然后减去对应天数
  local dow=$(date -j -f "%Y-%m-%d" "$date" +%u 2>/dev/null || echo "1")
  local days_to_monday=$((dow - 1))
  if [ $days_to_monday -eq 0 ]; then
    echo "$date"
  else
    date -j -v-${days_to_monday}d -f "%Y-%m-%d" "$date" +%Y-%m-%d 2>/dev/null || echo "$date"
  fi
}

# 获取周日日期
get_sunday() {
  local date="$1"
  local dow=$(date -j -f "%Y-%m-%d" "$date" +%u 2>/dev/null || echo "7")
  local days_to_sunday=$((7 - dow))
  if [ $days_to_sunday -eq 0 ]; then
    echo "$date"
  else
    date -j -v+${days_to_sunday}d -f "%Y-%m-%d" "$date" +%Y-%m-%d 2>/dev/null || echo "$date"
  fi
}

# 获取前一天/后一天
get_prev_day() {
  local date="$1"
  date -j -v-1d -f "%Y-%m-%d" "$date" +%Y-%m-%d 2>/dev/null || echo ""
}

get_next_day() {
  local date="$1"
  date -j -v+1d -f "%Y-%m-%d" "$date" +%Y-%m-%d 2>/dev/null || echo ""
}

# 获取前一周/后一周的周一
get_prev_week() {
  local monday="$1"
  date -j -v-7d -f "%Y-%m-%d" "$monday" +%Y-%m-%d 2>/dev/null || echo ""
}

get_next_week() {
  local monday="$1"
  date -j -v+7d -f "%Y-%m-%d" "$monday" +%Y-%m-%d 2>/dev/null || echo ""
}

# 获取前一月/后一月
get_prev_month() {
  local month="$1"  # YYYY-MM
  local year="${month%-*}"
  local mon="${month#*-}"
  if [ "$mon" = "01" ]; then
    echo "$((year - 1))-12"
  else
    printf "%04d-%02d" "$year" "$((10#$mon - 1))"
  fi
}

get_next_month() {
  local month="$1"  # YYYY-MM
  local year="${month%-*}"
  local mon="${month#*-}"
  if [ "$mon" = "12" ]; then
    echo "$((year + 1))-01"
  else
    printf "%04d-%02d" "$year" "$((10#$mon + 1))"
  fi
}

# 为 daily note 添加关联
link_daily() {
  local file="$1"
  local date=$(basename "$file" .md)
  local year_month="${date%-*}"

  local prev_day=$(get_prev_day "$date")
  local next_day=$(get_next_day "$date")
  local monday=$(get_monday "$date")

  # 构建导航行
  local nav_line=""
  if [ -n "$prev_day" ]; then
    nav_line="[[${prev_day}|← 昨天]]"
  fi
  nav_line="$nav_line | [[${monday}|↑ 本周]] | [[${year_month}|↑ 本月]]"
  if [ -n "$next_day" ]; then
    nav_line="$nav_line | [[${next_day}|明天 →]]"
  fi

  # 检查文件是否已有导航行
  if grep -qE "← 昨天|明天 →|↑ 本周|↑ 本月" "$file" 2>/dev/null; then
    if $DRY_RUN; then
      echo "[DRY-RUN] 更新 $date 的导航行"
    else
      # 删除旧的导航行，在标题后插入新的
      sed -i.bak -E '/← 昨天|明天 →|↑ 本周|↑ 本月/d' "$file"
      sed -i.bak "/^# $date/a\\
$nav_line
" "$file"
      squeeze_blank_lines "$file"
      rm -f "${file}.bak"
      echo "✓ 更新 $date"
    fi
  else
    if $DRY_RUN; then
      echo "[DRY-RUN] 添加 $date 的导航行"
    else
      # 在标题后插入导航行
      sed -i.bak "/^# $date/a\\
$nav_line
" "$file"
      rm -f "${file}.bak"
      echo "✓ 添加 $date"
    fi
  fi
}

# 为 weekly note 添加关联
link_weekly() {
  local file="$1"
  local monday=$(basename "$file" .md)
  local sunday=$(get_sunday "$monday")
  local year_month="${monday%-*}"

  local prev_week=$(get_prev_week "$monday")
  local next_week=$(get_next_week "$monday")

  # 构建导航行
  local nav_line=""
  if [ -n "$prev_week" ]; then
    nav_line="[[${prev_week}|← 上周]]"
  fi
  nav_line="$nav_line | [[${year_month}|↑ 本月]]"
  if [ -n "$next_week" ]; then
    nav_line="$nav_line | [[${next_week}|下周 →]]"
  fi

  # 构建本周 daily notes 列表
  local daily_list="**本周日报**: "
  local current_date="$monday"
  for i in {0..6}; do
    if [ -f "$DAILY_DIR/${current_date}.md" ]; then
      daily_list="$daily_list [[${current_date}]]"
      [ $i -lt 6 ] && daily_list="$daily_list · "
    fi
    current_date=$(get_next_day "$current_date")
  done

  # 检查并更新
  if grep -qE "← 上周|下周 →|↑ 本月" "$file" 2>/dev/null; then
    if $DRY_RUN; then
      echo "[DRY-RUN] 更新 $monday 周报的导航"
    else
      sed -i.bak -E '/← 上周|下周 →|↑ 本月/d' "$file"
      sed -i.bak '/\*\*本周日报\*\*/d' "$file"
      # 在第一个 ## 之前插入
      awk -v nav="$nav_line" -v daily="$daily_list" '
        /^## / && !inserted { print nav; print ""; print daily; print ""; inserted=1 }
        { print }
      ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      squeeze_blank_lines "$file"
      rm -f "${file}.bak"
      echo "✓ 更新 $monday 周报"
    fi
  else
    if $DRY_RUN; then
      echo "[DRY-RUN] 添加 $monday 周报的导航"
    else
      awk -v nav="$nav_line" -v daily="$daily_list" '
        /^## / && !inserted { print nav; print ""; print daily; print ""; inserted=1 }
        { print }
      ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      echo "✓ 添加 $monday 周报"
    fi
  fi
}

# 为 monthly note 添加关联
link_monthly() {
  local file="$1"
  local month=$(basename "$file" .md)

  local prev_month=$(get_prev_month "$month")
  local next_month=$(get_next_month "$month")

  # 构建导航行
  local nav_line=""
  if [ -n "$prev_month" ]; then
    nav_line="[[${prev_month}|← 上月]]"
  fi
  if [ -n "$next_month" ]; then
    [ -n "$nav_line" ] && nav_line="$nav_line | "
    nav_line="${nav_line}[[${next_month}|下月 →]]"
  fi

  # 构建本月周报列表
  local weekly_list="**本月周报**: "
  local week_files=$(ls -1 "$WEEKLY_DIR" | grep "^${month}-" | sort)
  local first=true
  for week_file in $week_files; do
    local week_date="${week_file%.md}"
    if ! $first; then
      weekly_list="$weekly_list · "
    fi
    weekly_list="$weekly_list [[${week_date}]]"
    first=false
  done

  # 检查并更新
  if grep -qE "← 上月|下月 →" "$file" 2>/dev/null; then
    if $DRY_RUN; then
      echo "[DRY-RUN] 更新 $month 月报的导航"
    else
      sed -i.bak -E '/← 上月|下月 →/d' "$file"
      sed -i.bak '/\*\*本月周报\*\*/d' "$file"
      awk -v nav="$nav_line" -v weekly="$weekly_list" '
        /^## / && !inserted { print nav; print ""; print weekly; print ""; inserted=1 }
        { print }
      ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      squeeze_blank_lines "$file"
      rm -f "${file}.bak"
      echo "✓ 更新 $month 月报"
    fi
  else
    if $DRY_RUN; then
      echo "[DRY-RUN] 添加 $month 月报的导航"
    else
      awk -v nav="$nav_line" -v weekly="$weekly_list" '
        /^## / && !inserted { print nav; print ""; print weekly; print ""; inserted=1 }
        { print }
      ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      echo "✓ 添加 $month 月报"
    fi
  fi
}

# 主流程
main() {
  echo "=== 建立 Journal 三层时间关联体系 ==="
  echo ""

  if $DRY_RUN; then
    echo "【DRY-RUN 模式】不会实际修改文件"
    echo ""
  fi

  echo "1. 处理 daily notes..."
  for file in "$DAILY_DIR"/*.md; do
    [ -f "$file" ] || continue
    link_daily "$file"
  done

  echo ""
  echo "2. 处理 weekly notes..."
  for file in "$WEEKLY_DIR"/*.md; do
    [ -f "$file" ] || continue
    link_weekly "$file"
  done

  echo ""
  echo "3. 处理 monthly notes..."
  for file in "$MONTHLY_DIR"/*.md; do
    [ -f "$file" ] || continue
    link_monthly "$file"
  done

  echo ""
  echo "✅ 完成！"
}

main "$@"
