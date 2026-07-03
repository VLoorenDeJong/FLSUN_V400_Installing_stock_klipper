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

render_progress() {
  local current="$1"
  local total="$2"
  local width=30
  local percent=$(( current * 100 / total ))
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local bar=""

  for ((i=0; i<filled; i++)); do bar+="#"; done
  for ((i=0; i<empty; i++)); do bar+="-"; done

  printf '\r[%s] %3d%%  %d/%d  OK=%d ERR=%d' "$bar" "$percent" "$current" "$total" "$ok_count" "$err_count"
}

for idx in "${!scripts[@]}"; do
  f="${scripts[$idx]}"
  first_line="$(head -n 1 "$f" || true)"

  checker="bash"
  if [[ "$first_line" == *"/sh"* ]] && [[ "$first_line" != *"bash"* ]]; then
    checker="sh"
  fi

  if "$checker" -n "$f"; then
    ((ok_count++))
  else
    ((err_count++))
    failed_details+=("[$checker] $f")
  fi

  render_progress "$((idx + 1))" "$total_count"
done

echo
if [ "$err_count" -gt 0 ]; then
  echo ""
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
