# Kimi CLI Adapter

## Limitations

Kimi CLI (v1.4+) does NOT support:
- Hooks event system (no session-start/end lifecycle events)
- MCP server integration
- Global config directory for instructions

## How telos-swarm Works Around This

### Instruction Injection
- `sync.sh` generates `AGENTS.md` in the vault root directory
- Kimi reads `AGENTS.md` from cwd automatically
- For swarm sessions, `cli_pane_launch()` uses `--agent-file` to inject telos identity

### Alternative to Hooks
- No pre/post session hooks available
- Session logging must be done externally (e.g., tmux capture)
- Context injection happens at launch time via `--agent-file`

## Configuration

Kimi supports these relevant flags:
- `--agent-file <path>`: Custom agent specification file
- `--skills-dir <path>`: Custom skills directory
- `-p <prompt>`: Non-interactive mode with prompt
