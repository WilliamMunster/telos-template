# Obsidian CLI Usage

> 按需加载文档：当需要使用 Obsidian CLI 操作 vault 时注入

## CLI Path

```bash
OBS="/Applications/Obsidian.app/Contents/MacOS/Obsidian"
```

## Common Commands

```bash
# Read a note
$OBS read file=<name>

# Search vault
$OBS search query=<text>

# Append to daily note
$OBS daily:append content=<text>

# List tags
$OBS tags all counts

# Check backlinks
$OBS backlinks file=<name>
```

## Fallback Strategy

If Obsidian is not running, fall back to direct file operations on the vault directory:
- Vault path: `{{VAULT_PATH}}`
- Daily notes: `_journal/daily/YYYY-MM-DD.md`

## Known Issues

- Obsidian CLI (v1.12.0) 每次调用都启动完整 Electron 进程，macOS Dock 会多出图标
- 有 3s 超时 + 进程启动开销
- 对于确定性文档（如读取特定文件），直接文件操作更快更可靠
