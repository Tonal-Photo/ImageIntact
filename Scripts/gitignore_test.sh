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

# --- Summary ---
echo ""
echo "Results: $((PASS + FAIL)) tests, $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
