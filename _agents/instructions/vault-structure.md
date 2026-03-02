# telos Vault Structure

> 按需加载文档：当需要了解 vault 目录结构、文件组织方式时注入

## Directory Structure

```
_telos/          — identity, goals, beliefs, projects, lessons
_journal/        — daily notes
_agents/         — multi-CLI config source of truth
  identity.md    — who I am, goals, principles
  instructions/  — shared + CLI-specific instructions
  hooks/         — adapters for each CLI (claude, gemini, opencode, codex)
  commands/      — slash commands (symlinked to each CLI)
  skills/        — agent skills
  scripts/       — tools (telos-swarm multi-CLI orchestrator, etc.)
  sync.sh        — generate configs, link symlinks, verify health
work/personal/   — personal projects
work/company/    — company work
knowledge/       — tech knowledge, references
attachments/     — images
```

## Key Files

- `_telos/identity.md` — 个人身份定义（职业轨迹、核心能力）
- `_telos/goals.md` — 当前 OKR 目标追踪
- `_telos/beliefs.md` — 决策原则和工作方式
- `_telos/lessons.md` — 踩坑记录
- `_telos/projects.md` — 项目清单和路径
- `_telos/worklog.md` — 活跃工作项追踪
- `_agents/sync.sh` — 配置生成脚本

## File Organization Principles

- Obsidian 是知识中枢：原子化笔记 + 链接织网
- 不合并，用链接关联
- 项目统一存放 `~/project/`
