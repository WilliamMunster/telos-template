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
KIMI_DIR="$HOME/.kimi"

# Team vault detection
TEAM_VAULT_PATH="${TEAM_VAULT_PATH:-}"
if [ -z "$TEAM_VAULT_PATH" ] && [ -f "$VAULT_PATH/.telos-team-user" ]; then
  # Auto-detect team vault from .telos-team-user
  TEAM_VAULT_PATH="$VAULT_PATH"
fi

# Dry-run mode
DRY_RUN="${DRY_RUN:-false}"

backup() {
  mkdir -p "$BACKUP_DIR"
  for dir in "$CLAUDE_DIR" "$GEMINI_DIR" "$OPENCODE_DIR" "$CODEX_DIR" "$KIMI_DIR"; do
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

  # Claude Code: identity + shared + extra instructions + claude-specific
  if [ -d "$CLAUDE_DIR" ]; then
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; \
      [ -f "$AGENTS_DIR/instructions/work-quality.md" ] && { _apply_template_vars "$AGENTS_DIR/instructions/work-quality.md"; echo ""; }; \
      [ -f "$AGENTS_DIR/instructions/task-management.md" ] && { _apply_template_vars "$AGENTS_DIR/instructions/task-management.md"; echo ""; }; \
      [ -f "$AGENTS_DIR/instructions/vault-structure.md" ] && { _apply_template_vars "$AGENTS_DIR/instructions/vault-structure.md"; echo ""; }; \
      [ -f "$AGENTS_DIR/instructions/obsidian-cli.md" ] && { _apply_template_vars "$AGENTS_DIR/instructions/obsidian-cli.md"; echo ""; }; \
      _apply_template_vars "$AGENTS_DIR/instructions/claude-specific.md"; } \
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

  # Kimi: generate AGENTS.md in vault root (kimi reads from cwd)
  local vault_dir
  vault_dir="$(cd "$AGENTS_DIR/.." && pwd -P)"
  if [ -f "$AGENTS_DIR/instructions/kimi-specific.md" ]; then
    # Backup existing AGENTS.md if present
    if [ -f "$vault_dir/AGENTS.md" ]; then
      cp "$vault_dir/AGENTS.md" "$BACKUP_DIR/AGENTS.md.prev" 2>/dev/null || true
    fi
    { _apply_template_vars "$identity"; echo ""; _apply_template_vars "$shared"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/kimi-specific.md"; } \
      > "$vault_dir/AGENTS.md"
    echo "  + vault/AGENTS.md (for kimi)"
  fi
}

generate_team() {
  echo "[sync] Generating CLI instruction files with team context..."

  if [ -z "$TEAM_VAULT_PATH" ]; then
    echo "  x TEAM_VAULT_PATH not set. Run 'telos-team-join.sh' first or set TEAM_VAULT_PATH env var."
    return 1
  fi

  if [ ! -d "$TEAM_VAULT_PATH/_agents" ]; then
    echo "  x Team vault not found at $TEAM_VAULT_PATH"
    return 1
  fi

  local team_identity="$TEAM_VAULT_PATH/_agents/identity.md"
  local team_shared="$TEAM_VAULT_PATH/_agents/instructions/shared.md"
  local personal_identity="$AGENTS_DIR/identity.md"
  local personal_shared="$AGENTS_DIR/instructions/shared.md"

  # Backup before merge
  if [ "$DRY_RUN" != "true" ]; then
    for dir in "$CLAUDE_DIR" "$GEMINI_DIR" "$OPENCODE_DIR" "$CODEX_DIR" "$KIMI_DIR"; do
      if [ -d "$dir" ]; then
        local name=$(basename "$dir")
        mkdir -p "$BACKUP_DIR/$name"
        for f in CLAUDE.md GEMINI.md AGENTS.md; do
          [ -f "$dir/$f" ] && cp "$dir/$f" "$BACKUP_DIR/$name/" 2>/dev/null || true
        done
      fi
    done
    echo "  + Backup saved to $BACKUP_DIR"
  fi

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

  # Merge function: team identity + team shared + personal shared + CLI-specific
  _merge_instructions() {
    local cli_name="$1"
    local cli_dir="$2"
    local cli_file="$3"
    local cli_specific="$4"

    if [ ! -d "$cli_dir" ]; then
      return
    fi

    local output="$cli_dir/$cli_file"
    local tmp=$(mktemp)

    {
      echo "# Team + Personal Identity"
      echo ""
      echo "## Team Identity"
      echo ""
      _apply_template_vars "$team_identity"
      echo ""
      echo "## Team Shared Instructions"
      echo ""
      _apply_template_vars "$team_shared"
      echo ""
      if [ -f "$personal_identity" ]; then
        echo "## Personal Identity"
        echo ""
        _apply_template_vars "$personal_identity"
        echo ""
      fi
      if [ -f "$personal_shared" ]; then
        echo "## Personal Instructions"
        echo ""
        _apply_template_vars "$personal_shared"
        echo ""
      fi
      if [ -f "$cli_specific" ]; then
        echo "## $cli_name Specific Instructions"
        echo ""
        _apply_template_vars "$cli_specific"
      fi
    } > "$tmp"

    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY-RUN] Would write to $output"
      echo "  Preview (first 20 lines):"
      head -20 "$tmp" | sed 's/^/    /'
    else
      mv "$tmp" "$output"
      echo "  + $output"
    fi

    [ "$DRY_RUN" != "true" ] || rm -f "$tmp"
  }

  # Generate for each CLI
  _merge_instructions "Claude Code" "$CLAUDE_DIR" "CLAUDE.md" "$AGENTS_DIR/instructions/claude-specific.md"
  _merge_instructions "Gemini" "$GEMINI_DIR" "GEMINI.md" "$AGENTS_DIR/instructions/gemini-specific.md"
  _merge_instructions "opencode" "$OPENCODE_DIR" "AGENTS.md" "$AGENTS_DIR/instructions/opencode-specific.md"
  _merge_instructions "Codex" "$CODEX_DIR" "AGENTS.md" "$AGENTS_DIR/instructions/codex-specific.md"

  # Kimi: generate AGENTS.md in vault root (kimi reads from cwd)
  local vault_dir
  vault_dir="$(cd "$AGENTS_DIR/.." && pwd -P)"
  if [ -f "$AGENTS_DIR/instructions/kimi-specific.md" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY-RUN] Would write to $vault_dir/AGENTS.md (kimi)"
    else
      if [ -f "$vault_dir/AGENTS.md" ]; then
        cp "$vault_dir/AGENTS.md" "$BACKUP_DIR/AGENTS.md.prev" 2>/dev/null || true
      fi
      { _apply_template_vars "$AGENTS_DIR/identity.md"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/shared.md"; echo ""; _apply_template_vars "$AGENTS_DIR/instructions/kimi-specific.md"; } \
        > "$vault_dir/AGENTS.md"
      echo "  + vault/AGENTS.md (for kimi)"
    fi
  fi

  # Merge skills and commands (team ∪ personal, personal overrides on conflict)
  if [ "$DRY_RUN" != "true" ]; then
    _merge_skills_commands
  else
    echo "  [DRY-RUN] Would merge skills and commands (team ∪ personal)"
  fi
}

_merge_skills_commands() {
  echo "[sync] Merging skills and commands..."

  local team_skills="$TEAM_VAULT_PATH/_agents/skills"
  local team_commands="$TEAM_VAULT_PATH/_agents/commands"
  local personal_skills="$AGENTS_DIR/skills"
  local personal_commands="$AGENTS_DIR/commands"

  # Merge skills (symlink team skills, personal skills override)
  if [ -d "$CLAUDE_DIR/skills" ] && [ -d "$team_skills" ]; then
    for skill_dir in "$team_skills/"*/; do
      [ -d "$skill_dir" ] || continue
      local name=$(basename "$skill_dir")
      local target="$team_skills/$name"
      local link="$CLAUDE_DIR/skills/$name"

      # Check if personal skill exists
      if [ -d "$personal_skills/$name" ]; then
        echo "  ! Conflict: skill '$name' exists in both team and personal (using personal)"
        ln -sfn "$personal_skills/$name" "$link"
      else
        ln -sfn "$target" "$link"
        echo "  + linked team skill: $name"
      fi
    done
  fi

  # Merge commands (team commands + personal commands, personal overrides)
  if [ -d "$CLAUDE_DIR/commands" ] && [ -d "$team_commands" ]; then
    for cmd_file in "$team_commands/"*.md; do
      [ -f "$cmd_file" ] || continue
      local name=$(basename "$cmd_file")
      local link="$CLAUDE_DIR/commands/$name"

      # Check if personal command exists
      if [ -f "$personal_commands/$name" ]; then
        echo "  ! Conflict: command '$name' exists in both team and personal (using personal)"
        ln -sfn "$personal_commands/$name" "$link"
      else
        ln -sfn "$cmd_file" "$link"
        echo "  + linked team command: $name"
      fi
    done
  fi

  # Inject team-permission hook if exists
  local team_hook="$TEAM_VAULT_PATH/_agents/hooks/team-permission.sh"
  if [ -f "$team_hook" ]; then
    echo "  + Team permission hook available at $team_hook"
    echo "  ! Note: Hook installation is handled by telos-team-join.sh"
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

  # Check Codex skills symlinks
  if [ -d "$CODEX_DIR/skills" ]; then
    local codex_broken=0
    for link in "$CODEX_DIR/skills/"*; do
      [ -L "$link" ] && [ ! -e "$link" ] && codex_broken=$((codex_broken+1))
    done
    if [ $codex_broken -gt 0 ]; then
      echo "  x $codex_broken broken codex skill symlinks"; errors=$((errors+1))
    else
      echo "  + codex skill symlinks"
    fi
  fi

  # Check vault AGENTS.md (for kimi)
  local vault_dir_v
  vault_dir_v="$(cd "$AGENTS_DIR/.." && pwd -P)"
  if [ -f "$vault_dir_v/AGENTS.md" ]; then
    echo "  + vault/AGENTS.md (kimi)"
  else
    echo "  x vault/AGENTS.md missing (kimi needs this)"; errors=$((errors+1))
  fi

  # Check Kimi config dir
  if [ -d "$KIMI_DIR" ]; then
    echo "  + ~/.kimi exists"
  else
    echo "  ~ ~/.kimi not found (kimi may not be installed)"
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

knowledge_index() {
  # Auto-index knowledge/ directory (supports subdirectories, grouped by category)
  local knowledge_dir="$1"
  local readme="$knowledge_dir/README.md"
  if [ ! -d "$knowledge_dir" ] || [ ! -f "$readme" ]; then
    echo "[sync] knowledge/ or README.md not found, skipping index"
    return 0
  fi

  local index_content=""
  local count=0

  # Index root-level files first
  local root_files=""
  while IFS= read -r kfile; do
    local fname
    fname=$(basename "$kfile")
    [ "$fname" = "README.md" ] && continue
    local title
    title=$(grep -m1 '^# ' "$kfile" 2>/dev/null | sed 's/^# //' || true)
    [ -z "$title" ] && title="${fname%.md}"
    root_files="${root_files}- [${title}](${fname})\n"
    count=$((count+1))
  done < <(find "$knowledge_dir" -maxdepth 1 -name '*.md' -not -name 'README.md' | sort)

  # Index subdirectories (grouped by category)
  local subdir_content=""
  while IFS= read -r subdir; do
    [ -d "$subdir" ] || continue
    local category
    category=$(basename "$subdir")
    local sub_entries=""
    local sub_count=0
    while IFS= read -r kfile; do
      local fname
      fname=$(basename "$kfile")
      [ "$fname" = "README.md" ] && continue
      local title
      title=$(grep -m1 '^# ' "$kfile" 2>/dev/null | sed 's/^# //' || true)
      [ -z "$title" ] && title="${fname%.md}"
      sub_entries="${sub_entries}- [${title}](${category}/${fname})\n"
      sub_count=$((sub_count+1))
    done < <(find "$subdir" -maxdepth 1 -name '*.md' -not -name 'README.md' | sort)
    if [ $sub_count -gt 0 ]; then
      subdir_content="${subdir_content}\n### ${category}\n\n${sub_entries}"
      count=$((count+sub_count))
    fi
  done < <(find "$knowledge_dir" -mindepth 1 -maxdepth 1 -type d | sort)

  if [ $count -eq 0 ]; then
    index_content="_(empty — add .md files to this directory to populate)_"
  else
    index_content="${root_files}${subdir_content}"
  fi

  # Replace content between AUTO-INDEX markers
  local tmp_readme tmp_content
  tmp_readme=$(mktemp)
  tmp_content=$(mktemp)
  printf '%b' "$index_content" > "$tmp_content"
  awk -v cfile="$tmp_content" '
    /<!-- AUTO-INDEX-START -->/ { print; while((getline line < cfile) > 0) print line; skip=1; next }
    /<!-- AUTO-INDEX-END -->/ { skip=0 }
    !skip { print }
  ' "$readme" > "$tmp_readme"
  cp "$tmp_readme" "$readme"
  rm "$tmp_readme" "$tmp_content"
  echo "[sync] knowledge/README.md indexed ($count files)"
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

# --- Team doctor ---

doctor_team() {
  local team_vault="$1"
  echo "[doctor] Checking team member setup..."
  local errors=0

  if [ ! -d "$team_vault" ]; then
    echo "  x team vault not found: $team_vault"; return 1
  fi
  if ! command -v yq &>/dev/null; then
    echo "  x yq is required (brew install yq)"; return 1
  fi

  local team_yaml="$team_vault/_agents/team.yaml"
  if [ ! -f "$team_yaml" ]; then
    echo "  x team.yaml not found"; return 1
  fi
  echo "  + team.yaml exists"

  # Check .telos-team-user
  local user_file="$team_vault/.telos-team-user"
  if [ ! -f "$user_file" ]; then
    echo "  x .telos-team-user not found (run telos-team-join.sh)"; errors=$((errors+1))
  else
    local username role
    IFS=':' read -r username role < "$user_file"
    if [ -z "$username" ] || [ -z "$role" ]; then
      echo "  x .telos-team-user has invalid format"; errors=$((errors+1))
    else
      # Verify role matches team.yaml
      local yaml_role
      yaml_role=$(yq ".members.\"$username\".role" "$team_yaml" 2>/dev/null)
      if [ "$yaml_role" = "$role" ]; then
        echo "  + identity: $username ($role)"
      else
        echo "  x role mismatch: .telos-team-user says '$role', team.yaml says '$yaml_role'"; errors=$((errors+1))
      fi
    fi
  fi

  # Check pre-commit hook
  local pre_commit="$team_vault/.git/hooks/pre-commit"
  if [ -f "$pre_commit" ] && [ -x "$pre_commit" ]; then
    echo "  + pre-commit hook installed"
  else
    echo "  x pre-commit hook missing (run telos-team-join.sh)"; errors=$((errors+1))
  fi

  # Check post-commit hook (audit log)
  local post_commit="$team_vault/.git/hooks/post-commit"
  if [ -f "$post_commit" ] && [ -x "$post_commit" ]; then
    echo "  + post-commit hook installed (audit log)"
  else
    echo "  x post-commit hook missing (run telos-team-join.sh)"; errors=$((errors+1))
  fi

  # Check CLAUDE.md freshness (does it contain current team identity?)
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && [ -f "$team_vault/_agents/identity.md" ]; then
    if grep -q "^# === Team Identity ===" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
      # Check if a key line from identity.md appears in CLAUDE.md
      local first_content_line
      first_content_line=$(grep -m1 '^[^#].\{10,\}' "$team_vault/_agents/identity.md" 2>/dev/null || true)
      if [ -n "$first_content_line" ] && grep -qF "$first_content_line" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
        echo "  + CLAUDE.md team identity is up to date"
      else
        echo "  ~ CLAUDE.md may be stale (run: sync.sh generate --team $team_vault)"; errors=$((errors+1))
      fi
    else
      echo "  ~ CLAUDE.md has no team identity section (run: sync.sh generate --team $team_vault)"; errors=$((errors+1))
    fi
  fi

  if [ $errors -eq 0 ]; then
    echo "[doctor] All checks passed."
  else
    echo "[doctor] $errors issue(s) found."
    return 1
  fi
}

case "${1:-help}" in
  init)     init ;;
  generate) backup; generate ;;
  link)     backup; link ;;
  verify)   verify ;;
  diff)     diff_check ;;
  status)   status ;;
  all)      backup; generate; link; verify ;;
  team)
    shift
    # Parse --dry-run flag
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
      esac
    done
    generate_team
    if [ "$DRY_RUN" != "true" ]; then
      link
      verify
    fi
    ;;
  doctor)
    shift
    if [ $# -eq 0 ]; then echo "Usage: sync.sh doctor <team-vault-path>"; exit 1; fi
    doctor_team "$1"
    ;;
  help)
    echo "Usage: sync.sh {init|generate|link|verify|doctor|diff|status|all|team}"
    echo "  init      — First-time setup (create config, symlinks)"
    echo "  generate  — Generate CLI instruction files from source"
    echo "  link      — Create/fix symlinks (hooks, skills, commands)"
    echo "  verify    — Health check (symlinks, files)"
    echo "  doctor    — Check team member setup (identity, hooks, freshness)"
    echo "  diff      — Show what would change (dry-run)"
    echo "  status    — Show current configuration"
    echo "  all       — Backup + generate + link + verify"
    echo "  team      — Generate with team context (requires TEAM_VAULT_PATH)"
    echo "              Options: --dry-run (preview without writing)"
    ;;
  *) echo "Unknown command: $1"; exit 1 ;;
esac
