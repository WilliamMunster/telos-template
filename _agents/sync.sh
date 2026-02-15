#!/bin/bash
set -euo pipefail

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Load config if available
CONFIG_FILE="$AGENTS_DIR/config.env"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

VAULT_PATH="${VAULT_PATH:-$HOME/Documents/Obsidian Vault}"
BACKUP_DIR="$AGENTS_DIR/.backup/$(date +%Y%m%d-%H%M%S)"

# CLI config directories
CLAUDE_DIR="$HOME/.claude"
GEMINI_DIR="$HOME/.gemini"
OPENCODE_DIR="$HOME/.config/opencode"
CODEX_DIR="$HOME/.codex"

backup() {
  mkdir -p "$BACKUP_DIR"
  for dir in "$CLAUDE_DIR" "$GEMINI_DIR" "$OPENCODE_DIR" "$CODEX_DIR"; do
    if [ -d "$dir" ]; then
      local name=$(basename "$dir")
      mkdir -p "$BACKUP_DIR/$name"
      for f in CLAUDE.md GEMINI.md AGENTS.md; do
        [ -f "$dir/$f" ] && cp "$dir/$f" "$BACKUP_DIR/$name/" 2>/dev/null || true
      done
    fi
  done
  echo "[sync] Backup saved to $BACKUP_DIR"
}

generate() {
  echo "[sync] Generating CLI instruction files..."

  local identity="$AGENTS_DIR/identity.md"
  local shared="$AGENTS_DIR/instructions/shared.md"

  # Template variable replacement function
  _apply_template_vars() {
    local file="$1"
    if [ -f "$CONFIG_FILE" ] && [ -f "$file" ]; then
      local tmp=$(mktemp)
      cp "$file" "$tmp"
      # Replace template variables from config.env
      while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [ -z "$key" ] && continue
        value="${value%\"}"
        value="${value#\"}"
        if [[ "$OSTYPE" == darwin* ]]; then
          sed -i '' "s|{{${key}}}|${value}|g" "$tmp"
        else
          sed -i "s|{{${key}}}|${value}|g" "$tmp"
        fi
      done < "$CONFIG_FILE"
      cat "$tmp"
      rm "$tmp"
    else
      cat "$file"
    fi
  }

  # Claude Code: identity + shared + claude-specific
  if [ -d "$CLAUDE_DIR" ]; then
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/claude-specific.md"; } \
      > "$CLAUDE_DIR/CLAUDE.md"
    echo "  + ~/.claude/CLAUDE.md"
  fi

  # opencode: identity + shared + opencode-specific
  if [ -d "$OPENCODE_DIR" ] && [ -f "$AGENTS_DIR/instructions/opencode-specific.md" ]; then
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/opencode-specific.md"; } \
      > "$OPENCODE_DIR/AGENTS.md"
    echo "  + ~/.config/opencode/AGENTS.md"
  fi

  # Gemini: identity + shared + gemini-specific
  if [ -d "$GEMINI_DIR" ] && [ -f "$AGENTS_DIR/instructions/gemini-specific.md" ]; then
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/gemini-specific.md"; } \
      > "$GEMINI_DIR/GEMINI.md"
    echo "  + ~/.gemini/GEMINI.md"
  fi

  # Codex: identity + shared + codex-specific
  if [ -d "$CODEX_DIR" ] && [ -f "$AGENTS_DIR/instructions/codex-specific.md" ]; then
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/codex-specific.md"; } \
      > "$CODEX_DIR/AGENTS.md"
    echo "  + ~/.codex/AGENTS.md"
  fi
}

link() {
  echo "[sync] Creating/verifying symlinks..."

  # Claude skills
  if [ -d "$CLAUDE_DIR/skills" ] || mkdir -p "$CLAUDE_DIR/skills"; then
    for skill_dir in "$AGENTS_DIR/skills/"*/; do
      [ -d "$skill_dir" ] || continue
      local name=$(basename "$skill_dir")
      local target="$AGENTS_DIR/skills/$name"
      local link="$CLAUDE_DIR/skills/$name"
      if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$target" ]; then
        ln -sfn "$target" "$link"
        echo "  + linked skill: $name"
      fi
    done
  fi

  # Claude commands (vault — relative symlinks for portability)
  local vault_dir
  vault_dir="$(cd "$AGENTS_DIR/.." && pwd -P)"
  if [ -d "$AGENTS_DIR/commands" ]; then
    mkdir -p "$vault_dir/.claude/commands"
    for cmd_file in "$AGENTS_DIR/commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file")
      local link="$vault_dir/.claude/commands/$name"
      local rel_target="../../_agents/commands/$name"
      if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$rel_target" ]; then
        ( cd "$vault_dir/.claude/commands" && ln -sfn "$rel_target" "$name" )
        echo "  + linked vault command: $name"
      fi
    done
  fi

  # ~/.claude/commands — skip if already a symlink, otherwise create absolute symlinks
  local home_cmds="$HOME/.claude/commands"
  if [ -L "$home_cmds" ]; then
    :
  elif [ -d "$AGENTS_DIR/commands" ]; then
    mkdir -p "$home_cmds"
    for cmd_file in "$AGENTS_DIR/commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file")
      local abs_target
      abs_target="$(cd "$AGENTS_DIR/commands" && pwd -P)/$name"
      local link="$home_cmds/$name"
      if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$abs_target" ]; then
        ln -sfn "$abs_target" "$link"
        echo "  + linked claude command: $name"
      fi
    done
  fi

  # opencode commands
  if [ -d "$OPENCODE_DIR" ] && [ -d "$AGENTS_DIR/commands" ]; then
    mkdir -p "$OPENCODE_DIR/commands"
    for cmd_file in "$AGENTS_DIR/commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file")
      local link="$OPENCODE_DIR/commands/$name"
      if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$cmd_file" ]; then
        ln -sfn "$cmd_file" "$link"
        echo "  + linked opencode command: $name"
      fi
    done
  fi

  # Gemini commands (convert .md -> .toml)
  if [ -d "$GEMINI_DIR" ] && [ -d "$AGENTS_DIR/commands" ]; then
    mkdir -p "$GEMINI_DIR/commands"
    for cmd_file in "$AGENTS_DIR/commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file" .md)
      local toml_file="$GEMINI_DIR/commands/${name}.toml"
      local description prompt
      description=$(head -1 "$cmd_file")
      prompt=$(tail -n +2 "$cmd_file")
      prompt=$(echo "$prompt" | sed '/./,$!d')
      local new_content
      new_content=$(printf 'description = "%s"\nprompt = """\n%s\n"""' "$description" "$prompt")
      if [ ! -f "$toml_file" ] || [ "$new_content" != "$(cat "$toml_file")" ]; then
        printf '%s' "$new_content" > "$toml_file"
        echo "  + generated gemini command: ${name}.toml"
      fi
    done
  fi

  # Codex skills
  if [ -d "$CODEX_DIR/skills" ] && [ -d "$AGENTS_DIR/skills" ]; then
    for skill_dir in "$AGENTS_DIR/skills/"*/; do
      [ -d "$skill_dir" ] || continue
      local name=$(basename "$skill_dir")
      local target="$AGENTS_DIR/skills/$name"
      local link="$CODEX_DIR/skills/$name"
      if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$target" ]; then
        ln -sfn "$target" "$link"
        echo "  + linked codex skill: $name"
      fi
    done
  fi

  echo "[sync] Symlinks done."
}

verify() {
  echo "[sync] Verifying..."
  local errors=0

  # Check ~/.agents symlink
  if [ ! -L "$HOME/.agents" ]; then
    echo "  x ~/.agents is not a symlink"; errors=$((errors+1))
  elif [ "$(readlink "$HOME/.agents")" != "$AGENTS_DIR" ]; then
    echo "  x ~/.agents points to wrong target"; errors=$((errors+1))
  else
    echo "  + ~/.agents symlink"
  fi

  # Check Claude CLAUDE.md exists
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo "  + ~/.claude/CLAUDE.md"
  else
    echo "  x ~/.claude/CLAUDE.md missing"; errors=$((errors+1))
  fi

  # Check skills symlinks
  if [ -d "$CLAUDE_DIR/skills" ]; then
    local broken=0
    for link in "$CLAUDE_DIR/skills/"*; do
      [ -L "$link" ] && [ ! -e "$link" ] && broken=$((broken+1))
    done
    if [ $broken -gt 0 ]; then
      echo "  x $broken broken skill symlinks"; errors=$((errors+1))
    else
      echo "  + skill symlinks"
    fi
  fi

  # Check hook scripts exist and are executable
  local hook_errors=0
  for f in session-start.sh session-end.sh security-validator.sh prompt-context.sh \
           post-tool-tracker.sh pre-compact.sh notification-router.sh; do
    local script="$AGENTS_DIR/hooks/adapters/claude/$f"
    if [ ! -f "$script" ]; then
      echo "  x hook script missing: $f"; hook_errors=$((hook_errors+1))
    elif [ ! -x "$script" ]; then
      echo "  x hook script not executable: $f"; hook_errors=$((hook_errors+1))
    fi
  done
  if [ $hook_errors -eq 0 ]; then
    echo "  + hook scripts"
  else
    errors=$((errors+hook_errors))
  fi

  # Check settings.local.json exists and has hooks config
  local settings="$CLAUDE_DIR/settings.local.json"
  if [ -f "$settings" ]; then
    if grep -q '"hooks"' "$settings"; then
      echo "  + settings.local.json (hooks configured)"
    else
      echo "  x settings.local.json missing hooks config"; errors=$((errors+1))
    fi
  else
    echo "  x settings.local.json missing (run setup.sh)"; errors=$((errors+1))
  fi

  # Check vault-level settings.local.json does NOT contain hooks
  local vault_settings
  vault_settings="$(cd "$AGENTS_DIR/.." && pwd -P)/.claude/settings.local.json"
  if [ -f "$vault_settings" ] && grep -q '"hooks"' "$vault_settings"; then
    echo "  x vault settings.local.json contains hooks config (will override user-level hooks!)"; errors=$((errors+1))
  else
    echo "  + vault settings.local.json (no hooks conflict)"
  fi

  # Check vault command symlinks are relative
  local vault_dir
  vault_dir="$(cd "$AGENTS_DIR/.." && pwd -P)"
  if [ -d "$vault_dir/.claude/commands" ]; then
    local abs_links=0
    for link in "$vault_dir/.claude/commands/"*.md; do
      [ -L "$link" ] || continue
      local target=$(readlink "$link")
      if [[ "$target" == /* ]]; then
        abs_links=$((abs_links+1))
      fi
    done
    if [ $abs_links -gt 0 ]; then
      echo "  x $abs_links vault command symlinks use absolute paths"; errors=$((errors+1))
    else
      echo "  + vault command symlinks (relative)"
    fi
  fi

  # Check command symlinks
  if [ -d "$CLAUDE_DIR/commands" ]; then
    local cmd_broken=0
    for link in "$CLAUDE_DIR/commands/"*; do
      [ -L "$link" ] && [ ! -e "$link" ] && cmd_broken=$((cmd_broken+1))
    done
    if [ $cmd_broken -gt 0 ]; then
      echo "  x $cmd_broken broken command symlinks"; errors=$((errors+1))
    else
      echo "  + command symlinks"
    fi
  fi

  # Check Gemini GEMINI.md
  if [ -f "$GEMINI_DIR/GEMINI.md" ]; then
    echo "  + ~/.gemini/GEMINI.md"
  elif [ -d "$GEMINI_DIR" ]; then
    echo "  x ~/.gemini/GEMINI.md missing"; errors=$((errors+1))
  fi

  # Check Codex AGENTS.md
  if [ -f "$CODEX_DIR/AGENTS.md" ]; then
    echo "  + ~/.codex/AGENTS.md"
  elif [ -d "$CODEX_DIR" ]; then
    echo "  x ~/.codex/AGENTS.md missing"; errors=$((errors+1))
  fi

  # Check Gemini commands (each .md source should have a corresponding .toml)
  if [ -d "$GEMINI_DIR/commands" ] && [ -d "$AGENTS_DIR/commands" ]; then
    local missing_toml=0
    for cmd_file in "$AGENTS_DIR/commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file" .md)
      if [ ! -f "$GEMINI_DIR/commands/${name}.toml" ]; then
        echo "  x gemini command missing: ${name}.toml"; missing_toml=$((missing_toml+1))
      fi
    done
    if [ $missing_toml -eq 0 ]; then
      local md_count
      md_count=$(find "$AGENTS_DIR/commands" -name '*.md' -maxdepth 1 | wc -l | tr -d ' ')
      echo "  + gemini commands ($md_count matched)"
    else
      errors=$((errors+missing_toml))
    fi
  fi

  if [ $errors -eq 0 ]; then
    echo "[sync] All checks passed."
  else
    echo "[sync] $errors error(s) found."
    return 1
  fi
}

diff_check() {
  echo "[sync] Dry-run — showing what would change..."

  local identity="$AGENTS_DIR/identity.md"
  local shared="$AGENTS_DIR/instructions/shared.md"

  if [ -d "$CLAUDE_DIR" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    local tmp=$(mktemp)
    cat "$identity" "$shared" "$AGENTS_DIR/instructions/claude-specific.md" > "$tmp"
    if ! diff -q "$CLAUDE_DIR/CLAUDE.md" "$tmp" >/dev/null 2>&1; then
      echo "  ~ ~/.claude/CLAUDE.md would be updated"
      diff "$CLAUDE_DIR/CLAUDE.md" "$tmp" || true
    else
      echo "  = ~/.claude/CLAUDE.md is up to date"
    fi
    rm "$tmp"
  fi
}

init() {
  echo "[sync] First-time setup..."

  # Create config.env from template if not exists
  if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$AGENTS_DIR/config.env.example" ]; then
      cp "$AGENTS_DIR/config.env.example" "$CONFIG_FILE"
      echo "  + Created config.env from template"
      echo "  ! Please edit $CONFIG_FILE with your settings"
    else
      echo "  x config.env.example not found"
      return 1
    fi
  else
    echo "  = config.env already exists"
  fi

  # Create ~/.agents symlink
  if [ ! -L "$HOME/.agents" ]; then
    ln -sfn "$AGENTS_DIR" "$HOME/.agents"
    echo "  + Created ~/.agents symlink"
  else
    echo "  = ~/.agents symlink exists"
  fi

  # Create CLI config directories
  for dir in "$CLAUDE_DIR" "$GEMINI_DIR"; do
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir"
      echo "  + Created $dir"
    fi
  done

  echo "[sync] Init complete. Next: edit config.env, then run 'sync.sh all'"
}

status() {
  echo "[sync] Current configuration:"
  echo ""

  if [ -f "$CONFIG_FILE" ]; then
    echo "  config.env:"
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ ]] && continue
      [ -z "$key" ] && continue
      echo "    $key = $value"
    done < "$CONFIG_FILE"
  else
    echo "  config.env: not found (run 'sync.sh init')"
  fi

  echo ""
  echo "  Paths:"
  echo "    VAULT_PATH = ${VAULT_PATH}"
  echo "    AGENTS_DIR = ${AGENTS_DIR}"
  echo "    CLAUDE_DIR = ${CLAUDE_DIR}"
  echo "    GEMINI_DIR = ${GEMINI_DIR}"
}

case "${1:-help}" in
  init)     init ;;
  generate) backup; generate ;;
  link)     backup; link ;;
  verify)   verify ;;
  diff)     diff_check ;;
  status)   status ;;
  all)      backup; generate; link; verify ;;
  help)
    echo "Usage: sync.sh {init|generate|link|verify|diff|status|all}"
    echo "  init      — First-time setup (create config, symlinks)"
    echo "  generate  — Generate CLI instruction files from source"
    echo "  link      — Create/fix symlinks (hooks, skills, commands)"
    echo "  verify    — Health check (symlinks, files)"
    echo "  diff      — Show what would change (dry-run)"
    echo "  status    — Show current configuration"
    echo "  all       — Backup + generate + link + verify"
    ;;
  *) echo "Unknown command: $1"; exit 1 ;;
esac
