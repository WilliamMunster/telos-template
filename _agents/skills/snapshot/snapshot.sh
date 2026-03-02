#!/usr/bin/env bash
# /snapshot - 状态快照加载器
# 读取核心文件和最近 3 天 daily notes，生成结构化摘要

set -euo pipefail

VAULT_PATH="${VAULT_PATH:-$HOME/Documents/Obsidian Vault}"
TELOS_PATH="$VAULT_PATH/_telos"
JOURNAL_PATH="$VAULT_PATH/_journal/daily"

# 获取当前日期
TODAY=$(date +%Y-%m-%d)

# 输出标题
echo "# 状态快照 ($TODAY)"
echo ""

# 读取核心文件的辅助函数
read_file() {
    local file_path="$1"
    local section_title="$2"

    echo "## $section_title"
    echo ""

    if [[ ! -f "$file_path" ]]; then
        echo "[文件不存在: $file_path]"
        echo ""
        return
    fi

    if [[ ! -s "$file_path" ]]; then
        echo "[文件为空]"
        echo ""
        return
    fi

    # 读取文件内容，跳过 frontmatter
    local in_frontmatter=false
    local content=""

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if [[ "$in_frontmatter" == false ]]; then
                in_frontmatter=true
                continue
            else
                in_frontmatter=false
                continue
            fi
        fi

        if [[ "$in_frontmatter" == false ]]; then
            content+="$line"$'\n'
        fi
    done < "$file_path"

    # 输出内容（限制长度）
    if [[ -n "$content" ]]; then
        local total_lines=$(echo "$content" | wc -l | tr -d ' ')
        if [[ "$total_lines" -gt 100 ]]; then
            echo "$content" | head -n 100
            echo ""
            echo "[文件较大，仅显示前 100 行。完整内容见：$file_path]"
        else
            echo "$content"
        fi
    else
        echo "[无内容]"
    fi
    echo ""
}

# 1. 身份
read_file "$TELOS_PATH/identity.md" "身份"

# 2. 当前目标
read_file "$TELOS_PATH/goals.md" "当前目标"

# 3. 活跃项目
read_file "$TELOS_PATH/projects.md" "活跃项目"

# 4. 当前焦点
read_file "$TELOS_PATH/active-context.md" "当前焦点"

# 5. 当前挑战
read_file "$TELOS_PATH/challenges.md" "当前挑战"

# 6. 工作日志（最近 10 条）
echo "## 工作日志（最近条目）"
echo ""
if [[ -f "$TELOS_PATH/worklog.md" ]]; then
    # 提取最近的条目（假设每条以 ## 或 - 开头）
    grep -E "^(##|-)" "$TELOS_PATH/worklog.md" | tail -n 10 || echo "[无日志条目]"
else
    echo "[文件不存在]"
fi
echo ""

# 7. 近期活动（最近 3 天）
echo "## 近期活动（最近 3 天）"
echo ""

for i in 0 1 2; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        day_date=$(date -v-${i}d +%Y-%m-%d)
    else
        # Linux
        day_date=$(date -d "$i days ago" +%Y-%m-%d)
    fi

    daily_file="$JOURNAL_PATH/$day_date.md"

    echo "### $day_date"
    echo ""

    if [[ ! -f "$daily_file" ]]; then
        echo "[无记录]"
        echo ""
        continue
    fi

    if [[ ! -s "$daily_file" ]]; then
        echo "[文件为空]"
        echo ""
        continue
    fi

    # 读取 daily note，跳过 frontmatter，显示前 100 行
    in_frontmatter=false
    line_count=0
    total_lines=$(wc -l < "$daily_file")

    while IFS= read -r line && [[ $line_count -lt 100 ]]; do
        if [[ "$line" == "---" ]]; then
            if [[ "$in_frontmatter" == false ]]; then
                in_frontmatter=true
                continue
            else
                in_frontmatter=false
                continue
            fi
        fi

        if [[ "$in_frontmatter" == false ]]; then
            echo "$line"
            ((line_count++))
        fi
    done < "$daily_file"

    # 如果文件超过 100 行，显示提示
    if [[ "$total_lines" -gt 100 ]]; then
        echo ""
        echo "[文件较大，仅显示前 100 行。完整内容见：$daily_file]"
    fi

    echo ""
done

echo "---"
echo "状态快照加载完成"
