#!/usr/bin/env bash

set -euo pipefail

print_help() {
  echo "Usage:"
  echo "  cleanup-merged-branches.sh [options]"
  echo
  echo "Options:"
  echo "  --apply              Delete merged branches (default is dry run)"
  echo "  --branch <name>      Process only a specific remote branch"
  echo "  -h, --help           Show this help and exit"
  echo
  echo "Examples:"
  echo "  cleanup-merged-branches.sh"
  echo "  cleanup-merged-branches.sh --branch 777-feature"
  echo "  cleanup-merged-branches.sh --branch old-feature --apply"
}

APPLY=false
TARGET_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --branch)
      TARGET_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -n "$TARGET_BRANCH" ]]; then
  echo "Mode: single branch"
  echo "Target branch: $TARGET_BRANCH"
else
  echo "Mode: all remote branches"
fi
echo

git fetch --prune

get_default_branch() {
  if git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null; then
    git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||'
    return
  fi

  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "main"
    return
  fi

  if git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
    return
  fi

  echo "Unable to determine default branch"
  exit 1
}

gh_available() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

has_merged_pr_for_branch() {
  local branch="$1"

  if ! gh_available; then
    return 1
  fi

  gh pr list --state merged --head "$branch" --json number --jq 'length' 2>/dev/null | grep -qv '^0$'
}

ISSUES_FILE="issues.csv"
HAS_ISSUES_FILE=false

if [[ -f "$ISSUES_FILE" ]]; then
  HAS_ISSUES_FILE=true
fi

get_issue_status_for_branch() {
  local branch="$1"

  if ! $HAS_ISSUES_FILE; then
    echo "NO_FILE"
    return
  fi

  if [[ ! "$branch" =~ ^([0-9]{5}) ]]; then
    echo "NO_TASK"
    return
  fi

  local issue_id="${BASH_REMATCH[1]}"

  awk -F',' -v id="$issue_id" '
    NR > 1 && $1 == id { print tolower($3); found=1 }
    END { if (!found) print "NOT_FOUND" }
  ' "$ISSUES_FILE"
}

BASE_BRANCH=$(get_default_branch)
if [[ -n "$TARGET_BRANCH" ]]; then
  if ! git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
    echo "Error: branch 'origin/$TARGET_BRANCH' not found"
    exit 1
  fi
  REMOTE_BRANCHES="$TARGET_BRANCH"
else
  REMOTE_BRANCHES=$(git branch -r | grep -v ' -> ' | sed 's|origin/||')
fi

TOTAL_REMOTE_COUNT=0
PROTECTED_COUNT=0

DELETE_BY_GIT_COUNT=0
DELETE_BY_PR_COUNT=0
SAVE_BY_ISSUE_COUNT=0

TO_DELETE=()
SAVE_BRANCHES=()
SKIPPED=()
CLOSED_ISSUE_BRANCHES=()

echo "Default branch: $BASE_BRANCH"

if $HAS_ISSUES_FILE; then
  echo "Issues file: $ISSUES_FILE (enabled)"
else
  echo "Issues file: not found (disabled)"
fi
echo

for branch in $REMOTE_BRANCHES; do
  TOTAL_REMOTE_COUNT=$((TOTAL_REMOTE_COUNT + 1))

  if [[ "$branch" == "$BASE_BRANCH" ]] || [[ "$branch" == "test" ]]; then
    PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
    continue
  fi

  MERGED=false
  MERGED_BY=""

  if git merge-base --is-ancestor "origin/$branch" "origin/$BASE_BRANCH"; then
    MERGED=true
    MERGED_BY="GIT"
  elif has_merged_pr_for_branch "$branch"; then
    MERGED=true
    MERGED_BY="PR"
  fi

  ISSUE_STATUS=$(get_issue_status_for_branch "$branch")

  if $MERGED; then
    if $HAS_ISSUES_FILE && [[ "$ISSUE_STATUS" != "closed" && "$ISSUE_STATUS" != "NO_TASK" ]]; then
      SAVE_BRANCHES+=("$branch")
      SAVE_BY_ISSUE_COUNT=$((SAVE_BY_ISSUE_COUNT + 1))
      continue
    fi

    TO_DELETE+=("$branch")
    if [[ "$MERGED_BY" == "GIT" ]]; then
      DELETE_BY_GIT_COUNT=$((DELETE_BY_GIT_COUNT + 1))
    else
      DELETE_BY_PR_COUNT=$((DELETE_BY_PR_COUNT + 1))
    fi
    continue
  fi

  if [[ "$ISSUE_STATUS" == "closed" ]]; then
    CLOSED_ISSUE_BRANCHES+=("$branch")
  else
    SKIPPED+=("$branch")
  fi
done

if (( ${#TO_DELETE[@]} > 0 )); then
  echo "Branches to delete: ${#TO_DELETE[@]}"
  printf "%s\n" "${TO_DELETE[@]}"
  echo
fi

if (( ${#SAVE_BRANCHES[@]} > 0 )); then
  echo "Branches saved due to open/missing issues (safety): ${#SAVE_BRANCHES[@]}"
  printf "%s\n" "${SAVE_BRANCHES[@]}"
  echo
fi

if (( ${#SKIPPED[@]} > 0 )); then
  echo "Branches skipped (not merged): ${#SKIPPED[@]}"
  printf "%s\n" "${SKIPPED[@]}"
  echo
fi

if (( ${#CLOSED_ISSUE_BRANCHES[@]} > 0 )); then
  echo "Branches with closed issues but not merged (manual review): ${#CLOSED_ISSUE_BRANCHES[@]}"
  printf "%s\n" "${CLOSED_ISSUE_BRANCHES[@]}"
  echo
fi

echo "Summary:"
echo "Total remote branches checked: $TOTAL_REMOTE_COUNT"
echo "Protected branches skipped: $PROTECTED_COUNT"
echo "Branches to delete: ${#TO_DELETE[@]}"
echo "  - via git merge-base: $DELETE_BY_GIT_COUNT"
echo "  - via GitHub PRs: $DELETE_BY_PR_COUNT"
echo "Branches saved by issues safety check: $SAVE_BY_ISSUE_COUNT"
echo "Branches skipped (not merged): ${#SKIPPED[@]}"
echo "Branches with closed issues (manual review): ${#CLOSED_ISSUE_BRANCHES[@]}"
echo

if (( ${#TO_DELETE[@]} == 0 )); then
  exit 0
fi

if ! $APPLY; then
  echo "Dry run mode. Use --apply to delete branches"
  exit 0
fi

for branch in "${TO_DELETE[@]}"; do
  git push origin --delete "$branch"
done

echo "Done"
