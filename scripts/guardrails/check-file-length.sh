#!/bin/bash
set -u
cd "$(git rev-parse --show-toplevel)"
LIMIT=1000
status=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$LIMIT" ]; then
    echo "file-length: $file has $lines lines (limit $LIMIT). Split it by responsibility, see .agents/skills/code-rules/SKILL.md section 2."
    status=1
  fi
done < <(git ls-files --cached --others --exclude-standard '*.swift' '*.sh' '*.js' '*.css' '*.html' '*.yml' '*.yaml' '*.py' 'scripts/hooks/*')
[ "$status" -eq 0 ] && echo "file-length: ok"
exit "$status"
