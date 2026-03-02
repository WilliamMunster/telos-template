#!/bin/bash
# worktree.sh — Git worktree lifecycle management
# Source this file from telos-swarm.sh

SWARM_WORKTREE_DIR=".swarm-worktrees"

# Create a worktree for an agent
# Usage: worktree_create <project_dir> <agent_id> <base_branch>
worktree_create() {
  local project="$1" agent_id="$2" base_branch="${3:-main}"
  local branch="swarm/${agent_id}"
  local worktree_path="${project}/${SWARM_WORKTREE_DIR}/${agent_id}"

  if [ ! -d "$project/.git" ] && [ ! -f "$project/.git" ]; then
    echo "[worktree] $project is not a git repository" >&2
    return 1
  fi

  if [ -d "$worktree_path" ]; then
    echo "[worktree] $worktree_path already exists" >&2
    return 1
  fi

  # Create branch and worktree
  git -C "$project" worktree add -b "$branch" "$worktree_path" "$base_branch" 2>&1
  if [ $? -ne 0 ]; then
    echo "[worktree] Failed to create worktree" >&2
    return 1
  fi

  echo "$worktree_path"
}

# List all swarm worktrees for a project
worktree_list() {
  local project="$1"
  if [ ! -d "$project/.git" ] && [ ! -f "$project/.git" ]; then
    echo "[worktree] $project is not a git repository" >&2
    return 1
  fi
  git -C "$project" worktree list | grep "$SWARM_WORKTREE_DIR" || true
}

# Remove a worktree
worktree_remove() {
  local project="$1" agent_id="$2"
  local worktree_path="${project}/${SWARM_WORKTREE_DIR}/${agent_id}"
  local branch="swarm/${agent_id}"

  if [ ! -d "$worktree_path" ]; then
    echo "[worktree] $worktree_path does not exist" >&2
    return 1
  fi

  git -C "$project" worktree remove "$worktree_path" 2>&1
  # Delete the branch too
  git -C "$project" branch -d "$branch" 2>/dev/null
}

# Interactive merge of a worktree branch
worktree_merge() {
  local project="$1" agent_id="$2" target="${3:-main}"
  local branch="swarm/${agent_id}"

  echo "=== Merge Preview: $branch → $target ==="
  echo ""
  git -C "$project" log --oneline "$target..$branch" 2>/dev/null
  echo ""
  git -C "$project" diff --stat "$target..$branch" 2>/dev/null
  echo ""

  read -p "Proceed with merge? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git -C "$project" checkout "$target" && \
    git -C "$project" merge --no-ff "$branch" -m "Merge swarm/$agent_id into $target"
  else
    echo "Merge cancelled."
  fi
}

# Clean all swarm worktrees for a project
worktree_clean() {
  local project="$1"

  local worktree_dir="${project}/${SWARM_WORKTREE_DIR}"
  if [ ! -d "$worktree_dir" ]; then
    echo "[worktree] No swarm worktrees found"
    return 0
  fi

  echo "Cleaning swarm worktrees in $project..."
  for wt in "$worktree_dir"/*/; do
    [ -d "$wt" ] || continue
    local agent_id
    agent_id=$(basename "$wt")
    echo "  Removing: $agent_id"
    worktree_remove "$project" "$agent_id"
  done

  # Remove the worktree directory if empty
  rmdir "$worktree_dir" 2>/dev/null

  # Prune stale worktree references
  git -C "$project" worktree prune 2>/dev/null
}
