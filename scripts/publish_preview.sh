#!/usr/bin/env bash
# Prepare a local gh-pages worktree containing the static preview.
# This script DOES NOT push to remote. Run it locally and then `git push origin gh-pages` when ready.

set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKTREE_DIR="$ROOT/.gh-pages"
PREVIEW_SRC_DIR="$ROOT/frontend/preview"
PUBLIC_DIR="$ROOT/frontend/public"
DB_FILE="$ROOT/database/menu.json"

echo "Preparing gh-pages worktree at $WORKTREE_DIR"
# remove existing worktree dir if present
if [ -d "$WORKTREE_DIR" ]; then
  echo "Cleaning existing worktree dir"
  rm -rf "$WORKTREE_DIR"
fi

# create gh-pages worktree (orphan branch) without switching current branch
# If gh-pages exists remotely, this will create a local tracking branch; otherwise it'll create an orphan branch
if git show-ref --verify --quiet refs/heads/gh-pages; then
  git worktree add -B gh-pages "$WORKTREE_DIR" gh-pages
else
  git worktree add -B gh-pages "$WORKTREE_DIR"
fi

# copy preview files
mkdir -p "$WORKTREE_DIR"
rsync -a --delete "$PREVIEW_SRC_DIR/" "$WORKTREE_DIR/"
# ensure menu json is accessible at /database/menu.json (we'll place it under database/)
mkdir -p "$WORKTREE_DIR/database"
cp "$DB_FILE" "$WORKTREE_DIR/database/menu.json"
# copy public uploads (images)
if [ -d "$PUBLIC_DIR/uploads" ]; then
  mkdir -p "$WORKTREE_DIR/frontend/public/uploads"
  rsync -a "$PUBLIC_DIR/uploads/" "$WORKTREE_DIR/frontend/public/uploads/"
fi

# commit changes in the worktree
cd "$WORKTREE_DIR"
git add -A
if git diff --staged --quiet; then
  echo "No changes to commit in gh-pages worktree"
else
  git commit -m "Build preview for gh-pages"
  echo "Committed preview in worktree at $WORKTREE_DIR. To publish, run:"
  echo "  git push origin gh-pages"
fi

echo "Done. Preview ready in $WORKTREE_DIR (local gh-pages branch)."
