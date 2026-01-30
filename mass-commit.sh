#!/usr/bin/env bash
set -euo pipefail

# mass-commit.sh
# Create many commits and push them (safe defaults: new branch).
# Usage: ./mass-commit.sh [--repo <url>] [--count N] [--branch name] [--to-default] [--no-push]
#        [--force-push] [--author-name NAME] [--author-email EMAIL] [--timestamped] [--allow-empty]
#
# Default behavior: clone repo, create a new branch named mass/commits-<ts>, create N commits by appending to commits.txt,
# and push that new branch.

DEFAULT_REPO_SSH="git@github.com:danigorlo0407/Base.git"
DEFAULT_REPO_HTTPS="https://github.com/danigorlo0407/Base.git"

# Defaults
repo="$DEFAULT_REPO_SSH"
NUM_COMMITS=100
BRANCH=""
BRANCH_PREFIX="mass/commits"
TO_DEFAULT=false
PUSH=true
FORCE_PUSH=false
AUTHOR_NAME="${GIT_AUTHOR_NAME:-}"
AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-}"
TIMESTAMPED=false
ALLOW_EMPTY=false
FILE="commits.txt"

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --repo <url>           Clone URL (SSH or HTTPS). Default: $DEFAULT_REPO_SSH
  --count N              Number of commits to create. Default: $NUM_COMMITS
  --branch <name>        Name of branch to create and push. Default: ${BRANCH_PREFIX}-<ts>
  --to-default           Make commits directly on the remote default branch (explicit and potentially disruptive).
  --no-push              Do not push the branch to remote (local-only).
  --force-push           Force push the branch (use with caution).
  --author-name NAME     Commit author name (overrides git config for this run).
  --author-email EMAIL   Commit author email (overrides git config for this run).
  --timestamped          Assign incrementing commit timestamps (deterministic times).
  --allow-empty          Create empty commits instead of modifying a file.
  -h, --help             Show this help and exit.
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2;;
    --count) NUM_COMMITS="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --to-default) TO_DEFAULT=true; shift;;
    --no-push) PUSH=false; shift;;
    --force-push) FORCE_PUSH=true; shift;;
    --author-name) AUTHOR_NAME="$2"; shift 2;;
    --author-email) AUTHOR_EMAIL="$2"; shift 2;;
    --timestamped) TIMESTAMPED=true; shift;;
    --allow-empty) ALLOW_EMPTY=true; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 1;;
  esac
done

# Validate numeric
if ! [[ "$NUM_COMMITS" =~ ^[0-9]+$ ]] || [ "$NUM_COMMITS" -le 0 ]; then
  echo "Invalid --count value: $NUM_COMMITS" >&2
  exit 1
fi

# Create temporary clone dir and cleanup
tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not in PATH" >&2
  exit 1
fi

echo "Cloning $repo..."
git clone --depth 1 "$repo" "$tmpdir"
cd "$tmpdir"

# Determine default branch name
default_branch=$(git remote show origin | awk -F': ' '/HEAD branch/ {print $2}' || true)
if [ -z "$default_branch" ]; then
  # fallback to origin/HEAD symbolic ref
  default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
  default_branch=${default_branch#origin/}
fi
if [ -z "$default_branch" ]; then
  default_branch="main"
fi
echo "Remote default branch: $default_branch"

# Fetch latest default branch
git fetch --quiet origin "$default_branch" || true

# Checkout the default branch as a base
git checkout --quiet -B "local_base_$default_branch" "origin/$default_branch" 2>/dev/null || git checkout --quiet -B "local_base_$default_branch" "$default_branch" || true

# Decide branch
if [ "$TO_DEFAULT" = true ]; then
  # Explicit: operate on default branch
  BRANCH="$default_branch"
  echo "Operating on remote default branch: $BRANCH (explicit --to-default)"
else
  if [ -z "$BRANCH" ]; then
    BRANCH="${BRANCH_PREFIX}-"+$(date +%s)
  fi
  echo "Creating feature branch: $BRANCH"
git checkout -b "$BRANCH"
fi

# Ensure file exists if not using allow-empty
if [ "$ALLOW_EMPTY" = false ]; then
  : > "$FILE"
git add "$FILE"
  # initial commit if branch is newly created and empty tree
  if ! git rev-parse --verify --quiet HEAD >/dev/null; then
    # set author fallbacks for this commit if needed
    git -c user.name="${AUTHOR_NAME:-script}" -c user.email="${AUTHOR_EMAIL:-script@example.com}" commit -m "chore: ensure $FILE exists" --quiet || true
  fi
fi

# Prepare timestamps if requested
if [ "$TIMESTAMPED" = true ]; then
  START_TS=$(date +%s)
fi

echo "Creating $NUM_COMMITS commits..."
for i in $(seq 1 "$NUM_COMMITS"); do
  if [ "$ALLOW_EMPTY" = true ]; then
    # create an empty commit
    if [ "$TIMESTAMPED" = true ]; then
      COMMIT_TS=$((START_TS + i))
      GIT_AUTHOR_DATE="@$COMMIT_TS" GIT_COMMITTER_DATE="@$COMMIT_TS" \
        git -c user.name="${AUTHOR_NAME:-script}" -c user.email="${AUTHOR_EMAIL:-script@example.com}" commit --allow-empty -m "chore: add commit #$i" --quiet
    else
      git -c user.name="${AUTHOR_NAME:-script}" -c user.email="${AUTHOR_EMAIL:-script@example.com}" commit --allow-empty -m "chore: add commit #$i" --quiet
    fi
  else
    echo "Commit #$i" >> "$FILE"
git add "$FILE"
    if [ "$TIMESTAMPED" = true ]; then
      COMMIT_TS=$((START_TS + i))
      GIT_AUTHOR_DATE="@$COMMIT_TS" GIT_COMMITTER_DATE="@$COMMIT_TS" \
        git -c user.name="${AUTHOR_NAME:-script}" -c user.email="${AUTHOR_EMAIL:-script@example.com}" commit -m "chore: add commit #$i" --quiet
    else
      git -c user.name="${AUTHOR_NAME:-script}" -c user.email="${AUTHOR_EMAIL:-script@example.com}" commit -m "chore: add commit #$i" --quiet
    fi
  fi
done

# Push handling
if [ "$PUSH" = true ]; then
  echo "Pushing branch $BRANCH to origin..."
  if [ "$FORCE_PUSH" = true ]; then
    git push --force origin "$BRANCH"
  else
    # normal push
    set +e
    git push origin "$BRANCH"
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      echo "Push failed (non-fast-forward or remote rejection)."
      echo "You can retry with --force-push (unsafe) or push the created branch manually."
      exit $rc
    fi
  fi
  echo "Push complete."
else
  echo "Skipping push (--no-push). Branch is local: $BRANCH"i

echo "Done. Created $NUM_COMMITS commits on branch: $BRANCH

