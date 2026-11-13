#!/bin/bash
set -u
cd "$(git rev-parse --show-toplevel)"
status=0

report() {
  echo "no-comments: $1"
  status=1
}

scan_slash() {
  local hits
  hits=$(grep -nE '^[[:space:]]*(//|/\*|\*/)|[^:"/]//[[:space:]]|[^:"/]//$|/\*[^/]*$' "$1" | grep -vE 'https?://')
  [ -n "$hits" ] && while IFS= read -r line; do report "$1:$line"; done <<< "$hits"
}

scan_hash() {
  local hits
  hits=$(grep -nE '^[[:space:]]*#' "$1" | grep -vE '^1:#!')
  [ -n "$hits" ] && while IFS= read -r line; do report "$1:$line"; done <<< "$hits"
}

scan_html() {
  local hits
  hits=$(grep -n '<!--' "$1")
  [ -n "$hits" ] && while IFS= read -r line; do report "$1:$line"; done <<< "$hits"
}

while IFS= read -r file; do
  [ -f "$file" ] || continue
  case "$file" in
    *.swift|*.js|*.css) scan_slash "$file" ;;
    *.sh|*.yml|*.yaml|*.py|scripts/hooks/*) scan_hash "$file" ;;
    *.html) scan_html "$file" ;;
  esac
done < <(git ls-files --cached --others --exclude-standard '*.swift' '*.js' '*.css' '*.sh' '*.yml' '*.yaml' '*.py' '*.html' 'scripts/hooks/*')

if [ "$status" -ne 0 ]; then
  echo "no-comments: remove these comments and let names explain the code, see .agents/skills/code-rules/SKILL.md section 1."
else
  echo "no-comments: ok"
fi
exit "$status"
