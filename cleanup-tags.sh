#!/usr/bin/env bash

set -euo pipefail

print_help() {
  echo "Usage:"
  echo "  cleanup-tags.sh [options]"
  echo
  echo "Options:"
  echo "  --keep <number>    Number of latest tags to keep (default: $KEEP_COUNT)"
  echo "  --months <number>  Do not delete tags newer than this number of months (default: $MONTHS)"
  echo "  --apply            Perform deletion (default is dry run)"
  echo "  -h, --help         Show this help and exit"
  echo
  echo "Examples:"
  echo "  cleanup-tags.sh"
  echo "  cleanup-tags.sh --keep 50 --months 6"
  echo "  cleanup-tags.sh --keep 50 --months 6 --apply"
}

KEEP_COUNT=50
MONTHS=6
TAG_REGEX='^[0-9]{4}$'
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP_COUNT="$2"
      shift 2
      ;;
    --months)
      MONTHS="$2"
      shift 2
      ;;
    --apply)
      APPLY=true
      shift
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

ALL_TAGS=$(git tag || true)

VALID_TAGS=$(echo "$ALL_TAGS" | grep -E "$TAG_REGEX" || true)
INVALID_TAGS=$(echo "$ALL_TAGS" | grep -Ev "$TAG_REGEX" || true)

if [[ -z "$VALID_TAGS" ]]; then
  echo "No matching tags found"
  exit 0
fi

SORTED_TAGS=$(echo "$VALID_TAGS" | sort -n)
TOTAL=$(echo "$SORTED_TAGS" | wc -l | tr -d ' ')

if (( TOTAL <= KEEP_COUNT )); then
  echo "Nothing to delete. Total tags: $TOTAL"
  exit 0
fi

DELETE_CANDIDATES=$(echo "$SORTED_TAGS" | head -n $((TOTAL - KEEP_COUNT)))
TO_KEEP=$(echo "$SORTED_TAGS" | tail -n "$KEEP_COUNT")

CUTOFF_TS=$(
  date -u -v-"$MONTHS"m +%s 2>/dev/null \
  || date -u -d "$MONTHS months ago" +%s
)

TO_DELETE=()
SKIPPED_RECENT=()

for tag in $DELETE_CANDIDATES; do
  COMMIT_TS=$(git log -1 --format=%ct "refs/tags/$tag")
  if [[ ! "$COMMIT_TS" =~ ^[0-9]+$ ]]; then
    echo "Invalid commit timestamp for tag $tag"
    continue
  fi
  if (( COMMIT_TS < CUTOFF_TS )); then
    TO_DELETE+=("$tag")
  else
    SKIPPED_RECENT+=("$tag")
  fi
done

KEEP_BY_COUNT_COUNT=$(echo "$TO_KEEP" | wc -l | tr -d ' ')
SKIPPED_RECENT_COUNT=${#SKIPPED_RECENT[@]}
TO_DELETE_COUNT=${#TO_DELETE[@]}

echo "Tags kept by count: $KEEP_BY_COUNT_COUNT"
echo "$TO_KEEP"
echo

if (( ${#SKIPPED_RECENT[@]} > 0 )); then
  echo "Tags skipped due to age: $SKIPPED_RECENT_COUNT"
  printf "%s\n" "${SKIPPED_RECENT[@]}"
  echo
fi

if (( ${#TO_DELETE[@]} == 0 )); then
  echo "No tags eligible for deletion"
  exit 0
fi

echo "Tags to delete: $TO_DELETE_COUNT"
printf "%s\n" "${TO_DELETE[@]}"
echo

if [[ -n "$INVALID_TAGS" ]]; then
  INVALID_COUNT=$(echo "$INVALID_TAGS" | wc -l | tr -d ' ')
  echo "Tags skipped due to invalid format (manual review required): $INVALID_COUNT"
  echo "$INVALID_TAGS"
  echo
fi

echo "Summary:"
echo "Total matching tags: $TOTAL"
echo "Tags kept by count: $KEEP_BY_COUNT_COUNT"
echo "Tags skipped due to age: $SKIPPED_RECENT_COUNT"
echo "Tags to delete: $TO_DELETE_COUNT"
echo

if ! $APPLY; then
  echo "Dry run mode. Use --apply to delete tags"
  exit 0
fi

for tag in "${TO_DELETE[@]}"; do
  git tag -d "$tag"
  git push origin ":refs/tags/$tag"
done

echo "Done"
