---
name: snapshot
description: 加载完整状态快照（身份、目标、项目、工作日志、近期活动）
triggers:
  - snapshot
  - 状态
  - 快照
  - 我是谁
  - 我在做什么
---

# /snapshot - 状态快照加载器

快速加载完整工作状态，包括身份、目标、活跃项目、当前焦点和近期活动。

## 使用场景

- 新会话开始时快速建立上下文
- 需要了解当前工作重点
- 检查最近的进展和活动
- 确认身份和目标对齐

## 执行方式

直接调用：`/snapshot`

## 实现

skill 会读取以下文件并生成结构化摘要：

### 核心文件（5 个）
- `{{VAULT_PATH}}/_telos/identity.md` - 身份定位
- `{{VAULT_PATH}}/_telos/goals.md` - 当前目标
- `{{VAULT_PATH}}/_telos/projects.md` - 活跃项目
- `{{VAULT_PATH}}/_telos/worklog.md` - 工作日志
- `{{VAULT_PATH}}/_telos/active-context.md` - 当前焦点

### 近期活动（最近 3 天）
- `{{VAULT_PATH}}/_journal/daily/YYYY-MM-DD.md`

## 输出格式

```markdown
# 状态快照 (YYYY-MM-DD)

## 身份
[identity.md 内容摘要]

## 当前目标
[goals.md 内容摘要]

## 活跃项目
[projects.md 内容摘要]

## 当前焦点
[active-context.md 内容摘要]

## 工作日志
[worklog.md 最近条目]

## 近期活动（最近 3 天）
### YYYY-MM-DD
[daily note 摘要]

### YYYY-MM-DD
[daily note 摘要]

### YYYY-MM-DD
[daily note 摘要]
```

## 边界处理

- 文件不存在：显示 `[文件不存在]`
- 文件为空：跳过该部分
- 格式异常：继续处理其他文件

## 性能目标

- 执行时间 < 30 秒
- 使用文件系统工具（cat/grep）而非 Obsidian CLI

## 实现脚本

见 [snapshot.sh](snapshot.sh)
