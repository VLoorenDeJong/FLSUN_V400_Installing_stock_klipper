#!/usr/bin/env bash
set -euo pipefail

# Auto-detect repo root from this script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
  REPO_ROOT="$SCRIPT_DIR"
  while [ "$REPO_ROOT" != "/" ] && [ ! -d "$REPO_ROOT/.git" ]; do
    REPO_ROOT="$(dirname "$REPO_ROOT")"
  done

  if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "Could not detect repository root from: $SCRIPT_DIR"
    exit 1
  fi
fi

# Skip hidden VCS and common virtual env folders.
EXCLUDE_DIRS=(
  "$REPO_ROOT/.git"
  "$REPO_ROOT/.venv"
  "$REPO_ROOT/venv"
)

find_cmd=(find "$REPO_ROOT" -type f -name "*.sh")
for ex in "${EXCLUDE_DIRS[@]}"; do
  find_cmd+=( -not -path "$ex/*" )
done

mapfile -t scripts < <("${find_cmd[@]}" | sort)

if [ "${#scripts[@]}" -eq 0 ]; then
  echo "No shell scripts found under: $REPO_ROOT"
  exit 0
fi

echo "Checking ${#scripts[@]} shell script(s) under: $REPO_ROOT"
echo

ok_count=0
err_count=0
total_count="${#scripts[@]}"
failed_details=()

for idx in "${!scripts[@]}"; do
  f="${scripts[$idx]}"
  first_line="$(head -n 1 "$f" || true)"

  checker="bash"
  if [[ "$first_line" == *"/sh"* ]] && [[ "$first_line" != *"bash"* ]]; then
    checker="sh"
  fi

  if "$checker" -n "$f"; then
    ((ok_count++))
    printf '\033[92mOK\033[0m      [%s] %s\n' "$checker" "$f"
  else
    ((err_count++))
    failed_details+=("[$checker] $f")
    printf '\033[31mFAILED\033[0m  [%s] %s\n' "$checker" "$f"
  fi
done

echo ""
if [ "$err_count" -gt 0 ]; then
  echo "Failed files:"
  for entry in "${failed_details[@]}"; do
    echo "  $entry"
  done
fi

echo "Summary: OK=$ok_count ERR=$err_count"

if [ "$err_count" -gt 0 ]; then
  exit 1
fi

exit 0
