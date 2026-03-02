# telos-swarm

Multi-CLI AI agent orchestrator (v0.5.0). 在 tmux 中并行运行多个 AI CLI（claude, gemini, codex, kimi），支持任务协调、质量门禁、多模板编排和生命周期 hooks。

## 安装

```bash
# 依赖
brew install yq tmux

# 软链到 PATH
ln -sf <your-vault>/_agents/scripts/telos-swarm/telos-swarm.sh ~/.local/bin/telos-swarm
```

## 快速开始

```bash
# 手动分配
telos-swarm quick --claude "架构设计" --gemini "调研" --codex "编码"

# Arena 辩论（自动跑完 3 阶段）
telos-swarm arena --auto --claude --gemini "evidence chain 怎么设计"

# 多轮 Arena
telos-swarm arena --auto --rounds 3 --claude --gemini "API 设计方案"

# 头脑风暴（跳过交叉审查，更轻量）
telos-swarm brainstorm --auto --claude --gemini --kimi "产品命名"

# 结对编程（编码→审查→修订）
telos-swarm pair --auto --claude --codex "实现用户认证模块"
```

## 架构

```
telos-swarm.sh
├── lib/cli.sh       CLI 检测、能力描述、pane 启动
├── lib/tmux.sh      tmux session/pane 管理、布局
├── lib/worktree.sh  git worktree 隔离
├── lib/task.sh      任务 CRUD、dispatch、poll、质量门禁、failover
├── lib/hooks.sh     生命周期 hooks 引擎
└── hooks/builtin/   内置 hook 脚本
```

## 命令

### 基础

| 命令 | 说明 |
|------|------|
| `start <yaml>` | 从 YAML 配置启动 |
| `quick [opts] "任务"...` | 快捷模式 |
| `add --<cli> "任务"` | 追加 agent pane |
| `status` | 显示状态 |
| `merge [agent_id]` | 合并 worktree |
| `stop` | 终止 session（触发 swarm_stop hook） |
| `clean` | 清理 session + worktree |

### 任务协调

| 命令 | 说明 |
|------|------|
| `task add --type <type> --assign <cli> "描述"` | 创建任务 |
| `task list` | 列出所有任务 |
| `task get <id>` | 查看任务详情 |
| `task dispatch [id]` | 分发就绪任务 |
| `task poll [timeout]` | 轮询等待完成（自动推进依赖链） |
| `task status` | 彩色状态面板 + 进度条 |
| `task retry <id>` | 重试失败任务 |

Task 类型：`coding` | `analysis` | `review` | `design` | `synthesis` | `free`

### 编排模板

| 命令 | 流程 |
|------|------|
| `arena [--auto] [--rounds N] --cli1 --cli2 "议题"` | 分析 → 交叉审查 → 综合 |
| `brainstorm [--auto] --cli... "议题"` | 独立分析 → 综合（跳过审查） |
| `pair [--auto] --coder --reviewer "任务"` | 编码 → 审查 → 修订 |
| `archive [--move]` | 归档产出到项目目录 |

## 质量门禁

任务完成后自动检查产出质量，失败则触发 failover 到 Claude：

| 检查项 | 规则 |
|--------|------|
| 最低行数 | coding ≥ 5 行，其他 ≥ 3 行 |
| 结构 | analysis/synthesis/review 至少 2 个 `## ` 标题 |
| 列表 | review 必须有 bullet 或编号列表 |
| 错误模式 | 行首匹配 `I cannot` / `抱歉，我无法` 等 |

## Hooks

swarm 生命周期事件系统，支持自定义脚本：

| 事件 | 触发时机 |
|------|----------|
| `swarm_start` | session 创建后 |
| `swarm_stop` | session 终止前 |
| `task_complete` | 单个任务完成/失败后 |
| `arena_complete` | arena/brainstorm/pair 全部完成后 |

Hook 发现顺序：session 级 → 全局级 → 内置。失败不阻塞主流程。

```bash
# 自定义 hook 示例
mkdir -p ~/.telos-swarm/hooks/task_complete
cat > ~/.telos-swarm/hooks/task_complete/notify.sh << 'EOF'
#!/bin/bash
echo "Task $SWARM_TASK_ID ($SWARM_TASK_CLI) → $SWARM_TASK_STATUS"
EOF
chmod +x ~/.telos-swarm/hooks/task_complete/notify.sh
```

内置 hooks：
- `swarm_stop` → 自动 append session 摘要到 daily note
- `arena_complete` → 自动归档产出到 vault

## Worktree 隔离

开发任务默认使用 git worktree 隔离：每个 agent 在独立分支工作，完成后通过 `telos-swarm merge` 合并。

头脑风暴/设计任务用 `--no-worktree` 跳过隔离。

## Failover

任务失败（超时或质量门禁不通过）时自动 failover 到 Claude team 接管。也可手动：

```bash
telos-swarm task retry <id>
telos-swarm add --claude "接管任务"
```

## 配置

见 `templates/swarm.yaml.example`。

## 支持的 CLI

| CLI | 特长 |
|-----|------|
| claude | 综合最强，支持 team，适合 TL/架构/编码/审查 |
| gemini | 1M 上下文，适合调研/文档分析/长文本 |
| codex | 沙盒执行，适合编码/重构/批量修改 |
| kimi | 中文强，长上下文，适合内容创作/翻译/头脑风暴 |
