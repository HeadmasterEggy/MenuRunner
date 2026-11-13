#!/bin/bash
set -u
branch="${1:-${GITHUB_HEAD_REF:-}}"
[ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD)
case "$branch" in
  main|HEAD) echo "branch-name: $branch, skipped"; exit 0 ;;
esac
fix_hint="Rename it: git branch -m <type>/<short-kebab-description>, type is feat, fix, refactor, docs or chore. See .agents/skills/code-rules/SKILL.md section 4."
if ! printf '%s' "$branch" | grep -qE '^(feat|fix|refactor|docs|chore)/[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo "branch-name: '$branch' is not <type>/<short-kebab-description>. $fix_hint"
  exit 1
fi
description="${branch#*/}"
if printf '%s' "$description" | grep -qE '(^|-)(claude|codex|cursor|copilot|gemini|chatgpt|gpt|devin)(-|$)'; then
  echo "branch-name: '$branch' names an AI tool. Describe the change instead, even when a tool assigned the name. $fix_hint"
  exit 1
fi
if printf '%s' "$description" | grep -qE '^(wip|tmp|test|temp|misc|update|changes|fixes)$|^(wip|tmp)-'; then
  echo "branch-name: '$branch' does not describe the change. $fix_hint"
  exit 1
fi
words=$(printf '%s' "$description" | tr '-' '\n' | grep -c .)
if [ "$words" -gt 6 ]; then
  echo "branch-name: '$branch' has $words words, keep it to about five. $fix_hint"
  exit 1
fi
echo "branch-name: $branch ok"
