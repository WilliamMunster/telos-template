# Kimi CLI Specific Instructions

## Configuration

Kimi CLI reads agent instructions from `AGENTS.md` in the current working directory, or via `--agent-file` flag.

```bash
kimi                          # reads ./AGENTS.md automatically
kimi --agent-file path.md     # custom agent spec
kimi --skills-dir ./skills    # custom skills directory
```

## Capabilities

- 中文理解和生成能力强，适合内容创作、翻译、头脑风暴、文档撰写
- 长上下文支持
- 支持 `--agent-file` 自定义 agent spec
- 支持 `--skills-dir` 指定 skills 目录

## Limitations (vs Claude/Gemini)

- 无 hooks 事件系统（不支持 session-start/end 等生命周期事件）
- 无 MCP server 集成
- 指令文件通过 cwd 的 AGENTS.md 注入，不支持全局配置目录

## Best Use Cases in telos-swarm

- 头脑风暴（brainstorm 模板）
- 中文内容创作和翻译
- 文档撰写和审查
- 作为 Arena 参与者提供多样化视角
