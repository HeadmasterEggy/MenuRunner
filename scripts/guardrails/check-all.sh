#!/bin/bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in check-file-length check-no-comments check-banned-apis check-skills check-branch-name; do
  "$here/$check.sh" "$@" || status=1
done
if [ "$status" -ne 0 ]; then
  echo "guardrails: failed"
else
  echo "guardrails: all passed"
fi
exit "$status"
