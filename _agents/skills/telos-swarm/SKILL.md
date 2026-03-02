---
name: telos-swarm
description: Multi-CLI AI agent orchestrator — 用 Bash 控制 telos-swarm 编排多个 AI CLI 协作
triggers:
  - swarm
  - 编排
  - 辩论
  - 头脑风暴
  - 结对
  - arena
  - brainstorm
  - pair
  - 让 claude 和 gemini
  - 多 agent
  - 多 CLI
---

# telos-swarm Skill

你可以通过 Bash 工具调用 `telos-swarm` 命令来编排多个 AI CLI（claude/gemini/codex/kimi）协作完成任务。

## 硬约束

1. **查询状态必须用 `--json`**：`telos-swarm task list --json` 和 `telos-swarm task get <id> --json`，禁止解析 `task status` 的 ANSI 彩色输出
2. **所有路径用绝对路径**，不要 cd 后用相对路径
3. **单条消息发送**：tmux pane 中的 CLI 每个 Enter 都是一次提交，不要拆分命令
4. **DONE 标记**：每个任务产出最后一行必须是 `<!-- SWARM:DONE -->`
5. **禁止 TL 自我分配**：TL 占着自己的 pane，dispatch 会往同一个 pane 发新 prompt 导致递归中断。

   **关键理解**：`:team` 模式只是标记任务的执行模式，**不会改变 dispatch 的行为**。dispatch 仍然会往对应 CLI 的 pane 发送 prompt。

   **错误示例**（会导致 TL 被打断）：
   ```bash
   # ❌ 错误：创建 claude:team 任务后 dispatch
   telos-swarm task add --type synthesis --assign claude:team "整合分析"
   telos-swarm task dispatch  # 这会往 pane 0 发 prompt，打断 TL
   ```

   **正确示例**：
   ```bash
   # ✅ 方案 A：TL 直接用 Claude Code 的 Task 工具
   # 在 Claude Code 中执行：
   Task(subagent_type="general-purpose", prompt="整合分析...", run_in_background=true)

   # ✅ 方案 B：只用 telos-swarm 分发给其他 CLI
   telos-swarm task add --type analysis --assign gemini "分析 A"
   telos-swarm task add --type analysis --assign codex "分析 B"
   telos-swarm task add --type analysis --assign kimi "分析 C"
   telos-swarm task dispatch  # 只分发给 gemini/codex/kimi
   # TL 手动整合结果，不通过 telos-swarm
   ```

   **判断规则**：
   - 如果任务分配给 TL 的 CLI（通常是 claude）→ 用 Claude Code Task 工具
   - 如果任务分配给其他 CLI（gemini/codex/kimi）→ 用 telos-swarm dispatch

   **非交互环境处理**：
   - `task dispatch` 会自动检测是否在交互式终端（TTY）中运行
   - 在非交互环境（如 CI/CD、脚本、后台任务）中，检测到 TL 自我分配时会默认拒绝，避免 `read` 阻塞
   - 如需强制继续，设置环境变量：`SWARM_FORCE_SELF_DISPATCH=1 telos-swarm task dispatch`
   - 建议：在自动化脚本中避免分配任务给 TL，只分配给 worker CLIs
   - 交互式确认仅在"无 worker pane 且在交互终端"时触发

   **语义一致性注意**：
   - 如果存在同 CLI 的 worker pane，任务会派发到 worker 而非 TL
   - 这会导致"名义上分配给 TL，实际执行在 worker"的语义不一致
   - 建议：明确使用 `--assign <cli>` 而非依赖 TL CLI 名称
6. **禁止擅自 stop**：不要因为 pane 里的 CLI 退出（显示 zsh/bash）就 `telos-swarm stop` 杀掉整个 session。正确做法是在对应 pane 里重启 CLI（`tmux send-keys -t <pane> "gemini" Enter`）
7. **启动必须在真实终端**：`telos-swarm quick`/`start` 会创建 tmux session 并 attach，必须由用户在真实终端执行。Claude Code 的 Bash 工具没有真终端（`not a terminal`），pane 尺寸会是 1x12 导致 CLI 启动失败。Claude Code 只负责后续编排（`task add`/`dispatch`/`poll`），不负责启动 session

## 快速命令表

| 命令 | 说明 |
|------|------|
| `telos-swarm quick --claude "待命" --gemini "待命"` | 快速启动 swarm |
| `telos-swarm task add --type <type> --assign <cli> [--depends id] "描述"` | 创建任务 |
| `telos-swarm task list --json` | 列出任务（JSON） |
| `telos-swarm task get <id> --json` | 查看任务详情（JSON） |
| `telos-swarm task dispatch [id]` | 分发就绪任务 |
| `telos-swarm task poll [timeout]` | 轮询等待完成 |
| `telos-swarm task retry <id>` | 重试失败任务 |
| `telos-swarm arena --auto --claude --gemini "议题"` | Arena 辩论 |
| `telos-swarm brainstorm --auto --cli... "议题"` | 头脑风暴 |
| `telos-swarm pair --auto --claude --codex "任务"` | 结对编程 |
| `telos-swarm archive` | 归档产出 |
| `telos-swarm stop` | 停止 swarm |

Task 类型：`coding` | `analysis` | `review` | `code_review` | `design` | `synthesis` | `free`

## 核心工作流

### 第 0 步：检查现有 session（每次必做）

在执行任何工作流之前，必须先检查是否已有运行中的 swarm session：

```bash
telos-swarm status 2>&1
```

- 如果有活跃 session → 直接使用，跳到工作流的任务创建步骤
- 如果没有 session → 告诉用户在真实终端执行 `telos-swarm quick ...` 启动，等用户确认后再继续
- **绝对不要在 Claude Code 的 Bash 里执行 `telos-swarm quick` 或 `telos-swarm start`**

### 工作流 1：模板模式（Arena / Brainstorm / Pair）

用户说"让 claude 和 gemini 辩论 X"或"头脑风暴 X"时，直接用一条 `--auto` 命令：

```bash
# Arena 辩论（分析 → 交叉审查 → 综合）
telos-swarm arena --auto --claude --gemini "API 设计方案"

# 多轮 Arena
telos-swarm arena --auto --rounds 3 --claude --gemini "架构选型"

# 头脑风暴（分析 → 综合，跳过交叉审查）
telos-swarm brainstorm --auto --claude --gemini --kimi "产品命名"

# 结对编程（编码 → 审查 → 修订）
telos-swarm pair --auto --claude --codex "实现认证模块"
```

前提：需要先有运行中的 swarm session（用户在终端启动）。

### 工作流 2：自由分配

用户给出多个独立任务时：

```bash
# 创建任务
telos-swarm task add --type analysis --assign claude:team "设计 API 接口"
telos-swarm task add --type analysis --assign gemini "调研竞品方案"

# 分发 + 轮询
telos-swarm task dispatch
telos-swarm task poll
```

### 工作流 3：自定义依赖链

用户需要多步骤、有依赖关系的编排时：

```bash
# 创建带依赖的任务链
telos-swarm task add --type design --assign claude:team "设计 API 接口"
# → 返回 001
telos-swarm task add --type analysis --assign gemini "调研竞品方案"
# → 返回 002
telos-swarm task add --type coding --assign codex --depends 001,002 "根据设计和调研结果编码实现"
# → 返回 003

# 分发 + 轮询（自动推进依赖链）
telos-swarm task dispatch
telos-swarm task poll 600
```

## 决策指南

| 用户意图 | 选择工作流 |
|----------|-----------|
| "让 X 和 Y 辩论/对比/PK" | 工作流 1 → `arena --auto` |
| "头脑风暴/集思广益" | 工作流 1 → `brainstorm --auto` |
| "X 写代码，Y 审查" | 工作流 1 → `pair --auto` |
| 多个独立任务，无依赖 | 工作流 2 → `task add` × N + `dispatch` |
| 有先后依赖的任务链 | 工作流 3 → `task add --depends` |
| 混合场景 | 先用工作流 3 建链，再 `dispatch` + `poll` |

## 错误处理

```bash
# 1. 检查任务状态
telos-swarm task list --json

# 2. 查看失败任务详情
telos-swarm task get <id> --json

# 3. 重试失败任务
telos-swarm task retry <id>

# 4. 如果 CLI 无响应，检查 tmux pane
tmux list-panes -t <session> -F '#{pane_id} #{pane_title}'
```

## 完整命令参考

详见 [references/commands.md](references/commands.md)
