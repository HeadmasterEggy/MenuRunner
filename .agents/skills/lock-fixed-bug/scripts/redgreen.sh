#!/bin/bash
set -uo pipefail
usage() {
  echo "usage: redgreen.sh [-b <base-ref>] '<check command>' <fixed-file>..."
  exit 2
}
base="origin/main"
if [ "${1:-}" = "-b" ]; then
  base="${2:-}"
  shift 2
fi
check="${1:-}"
[ -n "$check" ] || usage
shift
[ "$#" -gt 0 ] || usage
cd "$(git rev-parse --show-toplevel)"
for file in "$@"; do
  if git diff --quiet "$base" -- "$file"; then
    echo "redgreen: $file is unchanged against $base, so swapping it back proves nothing"
    exit 2
  fi
done
stash_dir=$(mktemp -d)
restore() {
  for file in "$@"; do
    if [ -e "$stash_dir/$file" ]; then
      mkdir -p "$(dirname "$file")"
      cp -p "$stash_dir/$file" "$file"
    else
      rm -f "$file"
    fi
  done
  rm -rf "$stash_dir"
}
trap 'restore "$@"' EXIT
for file in "$@"; do
  mkdir -p "$stash_dir/$(dirname "$file")"
  [ -e "$file" ] && cp -p "$file" "$stash_dir/$file"
  if git cat-file -e "$base:$file" 2>/dev/null; then
    git show "$base:$file" > "$file"
  else
    rm -f "$file"
  fi
done
echo "redgreen: red run with $* from $base"
bash -c "$check"
red=$?
for file in "$@"; do
  if [ -e "$stash_dir/$file" ]; then cp -p "$stash_dir/$file" "$file"; else rm -f "$file"; fi
done
echo "redgreen: green run with the fix"
bash -c "$check"
green=$?
echo "redgreen: tree=$(git rev-parse HEAD^{tree}) red_exit=$red green_exit=$green"
if [ "$red" -eq 0 ]; then
  echo "redgreen: the check passes on the old code, so it does not expose the bug"
  exit 1
fi
if [ "$green" -ne 0 ]; then
  echo "redgreen: the check still fails with the fix"
  exit 1
fi
echo "redgreen: ok, red before the fix and green after"
