#!/bin/bash
# builtin hook: arena_complete — copy outputs to vault archive directory
# Idempotency: skips if target directory has identical content (shasum)

VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"

[ -n "$SWARM_SESSION_DIR" ] || exit 0
[ -n "$SWARM_SESSION" ] || exit 0

src="$SWARM_SESSION_DIR/.swarm/outputs"
[ -d "$src" ] || exit 0

# Count source files
src_count=$(find "$src" -name '*.md' -maxdepth 1 | wc -l | tr -d ' ')
[ "$src_count" -eq 0 ] && exit 0

target="$VAULT/work/personal/swarm-outputs/$SWARM_SESSION"

# Idempotency: skip if target has identical content (shasum comparison)
if [ -d "$target" ]; then
  src_manifest=$(cd "$src" && shasum *.md 2>/dev/null | sort)
  target_manifest=$(cd "$target" && shasum *.md 2>/dev/null | sort)
  [ "$src_manifest" = "$target_manifest" ] && exit 0
fi

mkdir -p "$target"
cp "$src"/*.md "$target/" 2>/dev/null
echo "产出已归档到 $target/ ($src_count 个文件)"
