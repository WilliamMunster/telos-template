# Codex CLI Specific Instructions

## Notes

- Codex CLI reads AGENTS.md from ~/.codex/ (global) and project root (project-level)
- Skills in ~/.codex/skills/ or ~/.agents/skills/ (auto-discovered, needs SKILL.md with frontmatter)
- Slash commands via skills system (no separate commands/ directory)
- No hooks event system; TELOS context injected statically via AGENTS.md
- Config in ~/.codex/config.toml (TOML format, not JSON)
- MCP servers configured in config.toml under [mcp_servers.<name>]
