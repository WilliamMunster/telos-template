# Shared Instructions

## Vault Structure

```
_telos/          — identity, goals, beliefs, projects, lessons
_journal/        — daily notes
_agents/         — multi-CLI config source of truth
  identity.md    — who I am, goals, principles
  instructions/  — shared + CLI-specific instructions
  hooks/         — adapters for each CLI (claude, gemini, opencode, codex)
  commands/      — slash commands (symlinked to each CLI)
  skills/        — agent skills
  sync.sh        — generate configs, link symlinks, verify health
work/personal/   — personal projects
work/company/    — company work
knowledge/       — tech knowledge, references
attachments/     — images
```

## Obsidian CLI

This vault is managed by Obsidian 1.12+ with CLI enabled:

```
OBS="{{OBSIDIAN_PATH}}"
$OBS read file=<name>           # read a note
$OBS search query=<text>        # search vault
$OBS daily:append content=<text> # append to daily note
$OBS tags all counts            # list tags
$OBS backlinks file=<name>      # check backlinks
```

If Obsidian is not running, fall back to direct file operations on the vault directory.
