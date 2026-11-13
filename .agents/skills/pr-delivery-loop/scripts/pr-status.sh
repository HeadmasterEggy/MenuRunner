#!/bin/bash
set -euo pipefail
pr="${1:?usage: pr-status.sh <pr-number> [owner/repo]}"
repo="${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
info=$(gh pr view "$pr" -R "$repo" --json headRefOid,baseRefName,state,isDraft,mergeable -q '[.headRefOid, .baseRefName, .state, (.isDraft | tostring), .mergeable] | @tsv')
IFS=$'\t' read -r sha base state draft mergeable <<< "$info"
runs=$(gh api "repos/$repo/commits/$sha/check-runs?per_page=100" -q '.check_runs[] | "\(.name)=\(.conclusion // .status)"')
statuses=$(gh api "repos/$repo/commits/$sha/status" -q '.statuses[] | "\(.context)=\(.state)"')
behind=$(gh api "repos/$repo/compare/$base...$sha" -q .behind_by)
all=$(printf '%s\n%s\n' "$runs" "$statuses" | grep . || true)
bad=$(printf '%s\n' "$all" | grep -E '=(failure|error|cancelled|timed_out|action_required|startup_failure|stale)$' | tr '\n' ' ' || true)
pending=$(printf '%s\n' "$all" | grep -E '=(queued|in_progress|pending|waiting|requested)$' | tr '\n' ' ' || true)
echo "pr=#$pr state=$state draft=$draft mergeable=$mergeable head=${sha:0:7} base=$base"
echo "check-runs: $(printf '%s' "$runs" | tr '\n' ' ')"
echo "statuses: $(printf '%s' "$statuses" | tr '\n' ' ')"
echo "bad=[${bad% }] pending=[${pending% }] behind=$behind"
if [ -z "$all" ]; then
  echo "no checks reported for $sha yet; a missing check is not a pass"
  exit 1
fi
[ -z "$bad" ] && [ -z "$pending" ] && [ "$behind" = "0" ] && [ "$mergeable" != "CONFLICTING" ]
