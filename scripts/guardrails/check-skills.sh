#!/bin/bash
set -u
cd "$(git rev-parse --show-toplevel)"
status=0
fail() {
  echo "skills: $1"
  status=1
}
for dir in .agents/skills/*/; do
  name=$(basename "$dir")
  skill="$dir/SKILL.md"
  skill="${skill//\/\//\/}"
  if [ ! -f "$skill" ]; then
    fail "$dir has no SKILL.md"
    continue
  fi
  [ "$(head -n 1 "$skill")" = "---" ] || fail "$skill must start with a --- frontmatter line"
  front=$(awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$skill")
  declared=$(printf '%s\n' "$front" | sed -n 's/^name:[[:space:]]*//p' | head -n 1)
  [ "$declared" = "$name" ] || fail "$skill name '$declared' must match its folder '$name'"
  description=$(printf '%s\n' "$front" | sed -n 's/^description:[[:space:]]*//p' | head -n 1)
  if [ -z "$description" ]; then
    fail "$skill needs a one-line description"
  else
    printf '%s' "$description" | grep -qE 'Use (when|before|after|only when)' || fail "$skill description must say what it does and 'Use when ...'"
    [ "${#description}" -le 1024 ] || fail "$skill description is ${#description} characters, keep it under 1024"
  fi
  lines=$(wc -l < "$skill" | tr -d ' ')
  [ "$lines" -le 500 ] || fail "$skill has $lines lines, move detail into references/"
  grep -q "$name" AGENTS.md || fail "AGENTS.md does not list the $name skill; add it to the skills index"
  for path in $(grep -oE '`(Sources|scripts|assets|\.agents|\.github)/[^` ]+`' "$skill" | tr -d '`' | sort -u); do
    case "$path" in *'*'*|*'<'*|*'{'*) continue ;; esac
    [ -e "$path" ] || [ -e "$dir/${path#*/}" ] || fail "$skill points to $path, which does not exist"
  done
done
[ "$status" -eq 0 ] && echo "skills: ok"
exit "$status"
