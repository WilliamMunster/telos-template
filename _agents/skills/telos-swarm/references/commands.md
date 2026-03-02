# telos-swarm 完整命令参考

## 全局

```
telos-swarm help                    显示帮助
telos-swarm status                  当前 swarm 状态
telos-swarm stop                    终止 session
telos-swarm clean                   清理 session + worktree
telos-swarm archive [--move]        归档产出
```

## 启动

### quick — 快捷启动

```bash
telos-swarm quick [选项] "任务"...

选项:
  --tl <cli>              指定 TL（默认自动选择）
  --project <path>        项目目录
  --base <branch>         基础分支（默认 main）
  --no-worktree           不使用 worktree 隔离
  --layout grid|stack|auto  布局模式（默认 auto）
  --claude "任务"         手动分配给 claude
  --gemini "任务"         手动分配给 gemini
  --codex "任务"          手动分配给 codex
  --kimi "任务"           手动分配给 kimi
```

### start — YAML 配置启动

```bash
telos-swarm start <config.yaml>
```

### add — 追加 agent

```bash
telos-swarm add --<cli> "任务描述"
```

## 任务管理

### task add — 创建任务

```bash
telos-swarm task add --type <type> --assign <cli> [--depends id,id] [--mode solo|team] "描述"
```

参数:
- `--type`: coding | analysis | review | code_review | design | synthesis | free
- `--assign`: claude | gemini | codex | kimi（加 `:team` 启用子 agent，如 `claude:team`）
- `--depends`: 逗号分隔的依赖任务 ID（如 `001,002`）
- `--mode`: solo（默认）| team（Claude 子 agent 模式）

返回: 任务 ID（如 `001`）

### task list --json — 列出任务

```bash
telos-swarm task list --json
```

输出示例:
```json
[
  {"id":"001","type":"analysis","cli":"claude","mode":"solo","status":"done","quality":"pass","depends":""},
  {"id":"002","type":"review","cli":"gemini","mode":"solo","status":"active","quality":"pending","depends":"001"}
]
```

### task get \<id\> --json — 任务详情

```bash
telos-swarm task get 001 --json
```

输出示例:
```json
{
  "id":"001",
  "type":"analysis",
  "desc":"设计 API 接口",
  "cli":"claude",
  "mode":"solo",
  "status":"done",
  "depends":"",
  "output_file":".swarm/outputs/001.md",
  "quality":"pass",
  "output_exists":true,
  "done_marker":true
}
```

### task dispatch — 分发任务

```bash
telos-swarm task dispatch [id]    # 指定 ID 或分发所有就绪任务
```

### task poll — 轮询等待

```bash
telos-swarm task poll [timeout_seconds] [id...]
```

- 默认 timeout: 300s
- 自动推进依赖链（前置任务完成后自动 dispatch 后续任务）
- 质量门禁自动检查，失败自动 failover 到 Claude

### task retry — 重试

```bash
telos-swarm task retry <id>
```

重置为 pending 并重新 dispatch。

### task status — 状态总览（人类可读）

```bash
telos-swarm task status
```

注意：此命令输出含 ANSI 颜色，不适合程序解析。程序化查询请用 `--json`。

## 模板模式

### arena — 辩论

```bash
telos-swarm arena [--auto] [--rounds N] --<cli1> --<cli2> "议题"
```

流程：分析 → 交叉审查 → 综合（× N 轮）

### brainstorm — 头脑风暴

```bash
telos-swarm brainstorm [--auto] --<cli>... "议题"
```

流程：独立分析 → 综合（跳过交叉审查）

### pair — 结对编程

```bash
telos-swarm pair [--auto] --<coder_cli> --<reviewer_cli> "任务"
```

流程：编码 → 审查 → 修订

## 状态流转

```
pending → active → done
                 → failed → (retry) → pending
                          → (failover) → active (Claude 接管)
```

## 质量门禁

自动检查:
- 最低行数（coding 类型 +2）
- 结构检查（analysis/review 需要标题和列表）
- 错误模式检测（拒绝回答等）

失败后自动 failover 到 Claude pane。
