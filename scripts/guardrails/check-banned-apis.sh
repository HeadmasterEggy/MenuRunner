#!/bin/bash
set -u
cd "$(git rev-parse --show-toplevel)"
rules="scripts/guardrails/banned-apis.tsv"
status=0
tab=$(printf '\t')
while IFS="$tab" read -r pattern allowed message source; do
  [ -n "$pattern" ] || continue
  hits=$(git ls-files --cached --others --exclude-standard 'Sources/*.swift' | while IFS= read -r file; do
    printf '%s' "$file" | grep -qE "$allowed" && continue
    grep -nE "$pattern" "$file" | sed "s|^|$file:|"
  done)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while IFS= read -r hit; do echo "banned-api: $hit"; done
    echo "  fix: $message ($source)"
    status=1
  fi
done < "$rules"
[ "$status" -eq 0 ] && echo "banned-api: ok"
exit "$status"
