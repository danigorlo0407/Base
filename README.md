#!/bin/bash
set -euo pipefail

REPO_SSH="git@github.com:danigorlo0407/Base.git"
REPO_HTTPS="https://github.com/danigorlo0407/Base.git"

REPO="$REPO_SSH"
# REPO="$REPO_HTTPS"

TMPDIR=$(mktemp -d)
BRANCH="bulk-files-$(date +%Y%m%d-%H%M%S)"

git clone "$REPO" "$TMPDIR"
cd "$TMPDIR"

DEFAULT_BRANCH=$(git remote show origin | awk -F': ' '/HEAD branch/ {print $2}')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

git fetch origin "$DEFAULT_BRANCH"
git checkout -b "$BRANCH" "origin/$DEFAULT_BRANCH"

# create 100 tiny files and commit each one
for i in $(seq -w 1 100); do
  FNAME="commit-${i}.txt"
  echo "Commit file #${i}" > "$FNAME"
  git add "$FNAME"
  git commit -m "chore: add ${FNAME}"
done

git push --set-upstream origin "$BRANCH"

echo "Done. Created 100 commits (one per file) on branch: $BRANCH"
echo "Open a PR from $BRANCH into $DEFAULT_BRANCH if you want to merge."
