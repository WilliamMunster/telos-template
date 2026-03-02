# telos-swarm :team 语法改进方案

## 问题分析

### 当前实现

当前 `--assign claude:team` 的实现逻辑：

1. **语法解析**（`telos-swarm.sh:603-606`）：
   ```bash
   if echo "$assigned_cli" | grep -q ':team$'; then
     assigned_cli="${assigned_cli%:team}"
     mode="team"
   fi
   ```
   - 将 `claude:team` 拆分为 `assigned_cli=claude` 和 `mode=team`
   - 仅设置 MODE 标记，不改变 dispatch 行为

2. **Dispatch 行为**（`lib/task.sh:587-678`）：
   - 检测到任务分配给 TL 自己的 CLI 时，调用 `_task_dispatch_self()`
   - `_task_dispatch_self()` 输出结构化块，提示 TL 使用 Task subagent
   - **关键问题**：这个提示需要 TL 手动执行，不是自动化的

3. **Mode 标记的作用**（`lib/task.sh:667`）：
   ```bash
   [ "$MODE" = "team" ] && mode_hint=" (可用 Team spawn 子 agent)"
   ```
   - 仅在 dispatch 到其他 pane 时添加提示文本
   - 如果 dispatch 到 TL 自己，这个提示不会生效

### 核心问题

1. **语义误导**：`:team` 暗示"会自动调用子 agent"，但实际只是标记 + 提示
2. **行为不一致**：
   - 如果有独立的 claude worker pane → dispatch 到 worker，添加提示文本
   - 如果没有 worker pane → self-dispatch，输出结构化块，需要 TL 手动处理
3. **用户困惑**：TL 看到 `claude:team` 以为可以安全分配，实际上会打断自己的执行流
4. **文档矛盾**：`tl-prompt.md:54` 说"用 `:team` 模式让它 spawn 子 agent 执行"，但实际不会自动 spawn

### 根本原因

telos-swarm 是 tmux pane 编排工具，不理解各 CLI 的内部机制（如 Claude 的 Task subagent）。`:team` 试图跨越这个边界，导致语义模糊。

## 改进方案

### 方案 1：废弃 `:team` 语法（推荐）

**描述**：
- 移除 `claude:team` 语法支持
- 明确规定：TL 不应将任务分配给自己的 CLI
- 如果确实需要 TL 的 CLI 执行任务，用户应手动添加 worker pane

**语法示例**：
```bash
# 错误用法（会报错）
telos-swarm task add --assign claude "任务"  # 如果 TL 是 claude

# 正确用法
telos-swarm task add --assign gemini "任务"  # 分配给其他 CLI
```

**优点**：
- 语义清晰：telos-swarm 只负责 pane 编排，不涉及 CLI 内部机制
- 避免误用：强制用户理解 TL 不能自我分配的限制
- 简化代码：移除 `:team` 解析和 self-dispatch 逻辑
- 符合设计原则：单一职责，边界清晰

**缺点**：
- 灵活性降低：单 CLI 场景下无法使用 telos-swarm
- 需要用户手动管理 panes：如果想用 claude 执行任务，必须开独立 pane

**实施复杂度**：低
- 移除 `telos-swarm.sh:603-606` 的 `:team` 解析
- 移除 `lib/task.sh:551-583` 的 `_task_dispatch_self()`
- 在 `task_dispatch()` 中添加硬性检查，禁止分配给 TL
- 更新文档和 TL prompt

**向后兼容性**：
- 破坏性变更：现有使用 `claude:team` 的脚本会失败
- 迁移路径：用户需要添加 worker pane 或重新分配任务

---

### 方案 2：重命名为 `--mode manual`（次优）

**描述**：
- 将 `:team` 改为显式的 `--mode manual`
- 语义：标记任务需要"手动执行"，不通过 tmux dispatch
- TL 看到 manual 任务时，自己决定如何执行（spawn subagent、手动操作等）

**语法示例**：
```bash
# 创建任务时显式标记
telos-swarm task add --type coding --assign claude --mode manual "任务"

# dispatch 时跳过 manual 任务
telos-swarm task dispatch  # 只 dispatch 非 manual 任务

# TL 查看 manual 任务并手动处理
telos-swarm task list --json | jq '.[] | select(.mode=="manual")'
```

**优点**：
- 语义明确：`manual` 清楚表达"需要手动处理"
- 保留灵活性：TL 可以用 Task subagent 或其他方式执行
- 不破坏 telos-swarm 的职责边界：只是标记，不涉及 CLI 内部机制

**缺点**：
- 仍需 TL 手动介入：没有真正解决自动化问题
- 增加认知负担：用户需要理解 manual vs solo vs team 的区别
- 工作流割裂：manual 任务不在自动化流程中

**实施复杂度**：低
- 将 `:team` 改为 `--mode manual`
- 修改 `task_dispatch()` 跳过 manual 任务
- 更新文档和 TL prompt

**向后兼容性**：
- 破坏性变更：现有 `claude:team` 语法失效
- 迁移路径：替换为 `--mode manual`

---

### 方案 3：实现真正的自动化（复杂）

**描述**：
- 让 telos-swarm 理解各 CLI 的子 agent 机制
- 检测到 `claude:team` 时，自动构造调用 Claude Task subagent 的命令
- 扩展到其他 CLI（如 Gemini 的 multi-agent 功能）

**语法示例**：
```bash
# 用户视角：和普通分配一样
telos-swarm task add --assign claude:team "任务"

# telos-swarm 内部：检测到 :team，自动生成 Task subagent 调用
# 发送到 TL pane 的命令：
# /task "阅读 /path/to/prompt.md，将结果写到 /path/to/output.md"
```

**优点**：
- 用户体验最佳：`:team` 真正实现自动化
- 充分利用 CLI 能力：不需要额外的 worker pane
- 符合用户预期：`:team` 就是"自动调用子 agent"

**缺点**：
- 严重违反单一职责：telos-swarm 需要理解每个 CLI 的内部机制
- 维护成本高：每个 CLI 的子 agent 调用方式不同，需要分别适配
- 脆弱性高：CLI 更新可能导致 telos-swarm 失效
- 复杂度爆炸：需要处理各种边界情况（subagent 失败、输出格式等）

**实施复杂度**：高
- 为每个 CLI 实现 subagent 调用适配器
- 修改 `_task_dispatch_self()` 自动生成调用命令
- 处理 subagent 的输出和状态同步
- 大量测试和边界情况处理

**向后兼容性**：
- 兼容：现有 `claude:team` 语法继续工作，但行为改变（从提示变为自动执行）
- 风险：行为变化可能导致意外结果

---

### 方案 4：引入 `--external` 标记（折中）

**描述**：
- 新增 `--external` 标记，表示"任务由外部系统执行，不通过 telos-swarm dispatch"
- telos-swarm 只负责任务状态管理，不负责执行
- TL 或用户手动执行任务，完成后更新状态

**语法示例**：
```bash
# 创建 external 任务
telos-swarm task add --type coding --assign claude --external "任务"

# dispatch 时跳过 external 任务
telos-swarm task dispatch  # 只 dispatch 非 external 任务

# TL 手动执行（使用 Task subagent）
telos-swarm task get 001 --json  # 查看任务详情
# ... TL 使用 Task subagent 执行 ...

# 手动标记完成
telos-swarm task complete 001
```

**优点**：
- 职责清晰：telos-swarm 只管状态，不管执行方式
- 灵活性高：支持任何外部执行方式（subagent、手动、其他工具）
- 不破坏架构：保持 telos-swarm 的边界

**缺点**：
- 需要手动介入：没有自动化
- 增加操作步骤：需要手动标记完成
- 状态同步问题：外部执行失败时，telos-swarm 无法感知

**实施复杂度**：中
- 新增 `--external` 标记解析
- 修改 `task_dispatch()` 跳过 external 任务
- 新增 `task complete` 命令手动标记完成
- 更新文档和 TL prompt

**向后兼容性**：
- 兼容：新增功能，不影响现有语法
- 迁移路径：将 `claude:team` 替换为 `--external`

## 推荐方案

**推荐方案 1：废弃 `:team` 语法**

### 理由

1. **符合设计原则**：
   - telos-swarm 是 tmux pane 编排工具，职责是"分发任务到不同 pane"
   - 不应理解或依赖各 CLI 的内部机制（如 Claude 的 Task subagent）
   - 保持简单、可预测的行为

2. **避免误用**：
   - 当前 `:team` 语义模糊，用户以为是自动化，实际需要手动介入
   - 废弃后，用户会立即发现问题（报错），而不是静默失败

3. **简化维护**：
   - 移除 self-dispatch 逻辑，减少代码复杂度
   - 减少边界情况和潜在 bug

4. **强制最佳实践**：
   - 多 CLI 协作是 telos-swarm 的核心价值
   - 单 CLI 场景应该用该 CLI 的原生功能（如 Claude 的 Team）

### 替代方案

如果用户确实需要在单 CLI 环境下使用 telos-swarm：

1. **手动添加 worker pane**：
   ```bash
   # 在 tmux session 中添加新 pane
   tmux split-window -h -t swarm:0
   tmux send-keys -t swarm:0.1 "claude" Enter

   # 然后正常分配任务
   telos-swarm task add --assign claude "任务"
   ```

2. **使用 CLI 原生功能**：
   - 对于 Claude：直接使用 `/team` 命令
   - 对于 Gemini：使用其 multi-agent 功能
   - telos-swarm 适合跨 CLI 协作，不适合单 CLI 内部编排

## 实施计划

### Phase 1：代码清理（1-2 小时）

1. **移除 `:team` 语法解析**：
   - 删除 `telos-swarm.sh:603-606`
   - 删除 `lib/task.sh:551-583` (`_task_dispatch_self()`)
   - 删除 `lib/task.sh:667` (mode_hint)

2. **添加 TL 自我分配检查**：
   ```bash
   # 在 task_dispatch() 开头添加
   local tl_cli="${SWARM_TL_CLI:-}"
   if [ -n "$tl_cli" ] && [ "$ASSIGNED_CLI" = "$tl_cli" ]; then
     local worker_pane=""
     worker_pane=$(_find_pane_for_cli "$session_dir" "$ASSIGNED_CLI" "$tmux_session") || true
     if [ -z "$worker_pane" ]; then
       echo "[dispatch] 错误：任务 ${task_id} 分配给 TL 自己的 CLI (${tl_cli})。" >&2
       echo "[dispatch] 请分配给其他 CLI，或添加 ${tl_cli} worker pane。" >&2
       sed -i '' 's/^STATUS="[^"]*"/STATUS="failed"/' "$task_file"
       return 1
     fi
   fi
   ```

3. **更新 failover 逻辑**：
   - 保留 `lib/task.sh:1110-1119` 的 failover 逻辑
   - 但移除自动 self-dispatch，改为报错提示

### Phase 2：文档更新（30 分钟）

1. **更新 TL prompt**（`templates/tl-prompt.md`）：
   - 移除第 38 行的 `（加 :team 启用 Claude 子 agent）`
   - 修改第 54 行：
     ```markdown
     2. **禁止把任务分配给 TL 自己的 CLI**（会导致 dispatch 失败）。
        如果需要使用 TL 的 CLI，请在 tmux session 中添加该 CLI 的 worker pane。
     ```

2. **更新帮助文档**（`telos-swarm.sh:1117`）：
   ```bash
   Assign 支持: claude | gemini | codex | kimi
   ```

3. **更新示例**（`telos-swarm.sh:1155`）：
   ```bash
   telos-swarm task add --type coding --assign gemini "实现功能"
   ```

### Phase 3：测试验证（30 分钟）

1. **测试正常场景**：
   - 多 CLI 环境下正常分配任务
   - 验证 dispatch 和 poll 工作正常

2. **测试错误场景**：
   - 尝试分配给 TL 自己的 CLI
   - 验证报错信息清晰

3. **测试 worker pane 场景**：
   - 添加 TL CLI 的 worker pane
   - 验证可以正常分配任务

### Phase 4：发布和迁移（沟通）

1. **更新 CHANGELOG**：
   ```markdown
   ## Breaking Changes

   - 移除 `--assign claude:team` 语法
   - 禁止将任务分配给 TL 自己的 CLI（除非有 worker pane）

   ## Migration Guide

   - 如果之前使用 `claude:team`，请改为分配给其他 CLI
   - 或在 tmux session 中添加 claude worker pane
   ```

2. **通知用户**：
   - 说明变更原因和迁移方法
   - 提供 worker pane 设置指南

## 附录：其他方案的适用场景

虽然推荐方案 1，但其他方案在特定场景下也有价值：

- **方案 2（`--mode manual`）**：如果需要支持"任务占位符"（先创建任务，稍后手动执行）
- **方案 4（`--external`）**：如果需要与外部系统集成（如 CI/CD pipeline）
- **方案 3（真正自动化）**：如果 telos-swarm 演化为"AI CLI 编排平台"，需要深度集成各 CLI

当前阶段，保持简单和职责清晰更重要。
