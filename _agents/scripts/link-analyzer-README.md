# Link Analyzer - Obsidian 链接分析工具

## 概述

`link-analyzer.sh` 是一个用于分析和优化 Obsidian vault 链接结构的工具。它可以：

- 扫描孤立文件（无入链的文件）
- 按类型分类文件（TELOS/工作/知识库/日志/系统）
- 为孤立文件建议链接位置
- 生成完整的链接健康报告
- 快速健康检查

## 使用方法

### 快速健康检查

```bash
bash _agents/scripts/link-analyzer.sh check
```

输出示例：
```
=== Vault 链接健康检查 ===

总文件数: 227
孤立文件: 6 (排除系统文件)
链接覆盖率: 97.4%

✅ 健康状况：良好
少量文件需要建立链接。
```

### 扫描孤立文件

```bash
# 扫描所有孤立文件
bash _agents/scripts/link-analyzer.sh scan

# 排除系统文件
bash _agents/scripts/link-analyzer.sh scan --exclude-system
```

### 分析孤立文件

```bash
# 按类型分类孤立文件
bash _agents/scripts/link-analyzer.sh analyze --exclude-system
```

输出格式：`类型|文件路径`

### 为文件建议链接

```bash
bash _agents/scripts/link-analyzer.sh suggest "work/personal/telos/some-doc.md"
```

输出示例：
```
文件: work/personal/telos/some-doc.md
类型: work

建议链接位置:
  - 在 _telos/worklog.md 的相关工作项中引用
  - 在 _telos/projects.md 的相关项目中引用
  - 创建或更新同目录的 README.md 索引

相关文件（可能需要建立链接）:
  基于关键词搜索: telos openviking
    - ./_telos/projects.md
    - ./_telos/worklog.md
```

### 生成完整报告

```bash
# 生成报告并保存
bash _agents/scripts/link-analyzer.sh report --exclude-system > link-report.md

# 直接查看
bash _agents/scripts/link-analyzer.sh report --exclude-system | less
```

## 文件分类逻辑

工具会自动将文件分为以下类型：

| 类型 | 目录模式 | 建议链接位置 |
|------|----------|--------------|
| **system** | `_agents/commands/`, `_agents/instructions/`, `_templates/`, `_agents/.backup/` | 不需要链接（系统自动加载） |
| **telos** | `_telos/` | 在 identity.md, goals.md, strategies.md 中引用 |
| **work** | `work/`, `docs/` | 在 worklog.md, projects.md 中引用，或创建 README 索引 |
| **knowledge** | `knowledge/` | 在 goals.md 的相关目标中引用 |
| **journal** | `_journal/` | 通常不需要入链，除非是重要摘要 |
| **other** | 其他 | 根据内容判断 |

## 健康状况评级

| 孤立文件数 | 评级 | 说明 |
|-----------|------|------|
| 0 | 优秀 | 所有文件都已建立链接 |
| 1-9 | 良好 | 少量文件需要链接 |
| 10-29 | 一般 | 建议优化链接结构 |
| 30+ | 需要改进 | 大量文件缺少链接 |

## 集成到工作流

### 1. 定期检查

在 weekly-review 中添加链接健康检查：

```bash
echo "## 链接健康"
bash _agents/scripts/link-analyzer.sh check
```

### 2. 创建新文档后

创建重要文档后，立即检查建议的链接位置：

```bash
bash _agents/scripts/link-analyzer.sh suggest "path/to/new-doc.md"
```

### 3. Git pre-commit hook

在提交前自动检查链接健康（可选）：

```bash
#!/bin/bash
# .git/hooks/pre-commit

cd "$VAULT_ROOT"
orphans=$(bash _agents/scripts/link-analyzer.sh scan --exclude-system | wc -l)

if [ "$orphans" -gt 20 ]; then
  echo "警告: 发现 $orphans 个孤立文件，建议优化链接结构"
  echo "运行 'bash _agents/scripts/link-analyzer.sh report' 查看详情"
fi
```

## 原理说明

### 孤立文件检测

1. 扫描所有 `.md` 文件
2. 对每个文件，搜索 vault 中是否有 `[[filename]]` 或 `[[path/filename]]` 格式的链接
3. 如果没有任何入链，标记为孤立文件

### 系统文件识别

以下文件被视为系统文件，不需要手动链接：

- `_agents/commands/` - 命令定义，由 CLI 自动加载
- `_agents/instructions/` - 指令文件，按需触发加载
- `_agents/scripts/telos-swarm/templates/` - 脚本模板
- `_templates/` - Obsidian 模板
- `_agents/.backup/` - 历史备份
- `_agents/skills/*/SKILL.md` - Skill 定义
- `_agents/skills/*/AGENTS.md` - Agent 配置
- `_claude/CLAUDE.md` - Claude Code 主配置

### 链接建议算法

1. 根据文件路径判断类型
2. 根据类型给出通用建议
3. 提取文件中的关键词（标题、标签）
4. 在 `_telos/` 目录中搜索相关文件
5. 列出可能需要建立链接的文件

## 限制

- 只检测 Obsidian 格式的 `[[链接]]`，不检测 Markdown 格式的 `[文本](链接)`
- 关键词搜索仅在 `_telos/` 目录中进行
- 不会自动修改文件，只提供建议

## 相关文档

- [[vault-structure]] - Vault 目录结构说明
- [[CLAUDE.md]] - TELOS 系统配置
- [[sync.sh]] - 多 CLI 同步工具
