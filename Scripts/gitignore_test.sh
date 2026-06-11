#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# --- Characterization: nothing under .claude or .worktrees is tracked ---
char_output="$(git -C "$repo_root" ls-files .claude .worktrees)"
if [[ -z "$char_output" ]]; then
  echo "PASS: char case - .claude and .worktrees contain no tracked files"
  PASS=$((PASS + 1))
else
  echo "FAIL: char case - unexpected tracked files: $char_output"
  FAIL=$((FAIL + 1))
fi

# --- Ignore case: .worktrees/ and .claude/ must be gitignored ---
git -C "$repo_root" check-ignore -q .worktrees/ && {
  echo "PASS: ignore case - .worktrees/ is gitignored"
  PASS=$((PASS + 1))
} || {
  echo "FAIL: ignore case - .worktrees/ is NOT gitignored"
  FAIL=$((FAIL + 1))
}

git -C "$repo_root" check-ignore -q .claude/ && {
  echo "PASS: ignore case - .claude/ is gitignored"
  PASS=$((PASS + 1))
} || {
  echo "FAIL: ignore case - .claude/ is NOT gitignored"
  FAIL=$((FAIL + 1))
}

# --- Summary ---
echo ""
echo "Results: $((PASS + FAIL)) tests, $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
