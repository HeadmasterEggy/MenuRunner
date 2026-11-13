---
name: pr-delivery-loop
description: Takes one MenuRunner change from a fresh branch to a merged PR, with a done condition for every step, including several PRs at once and stacked PRs. Use when starting any change that will become a PR, when a PR needs syncing with main, and right before merging.
---

# PR delivery loop

Each step ends only when its done condition holds. Skipping a step is fine only if you say so in the PR.

## 1. Start from fresh main, in its own worktree

```sh
git fetch origin main
git worktree add -b <type>/<short-description> ../MenuRunner-<short-description> origin/main
```

- Done when: the new branch's base is the `origin/main` you just fetched and the worktree holds nothing else.
- Fetch again before every new branch. A branch cut from a stale main makes its diff look like it reverts PRs that merged since.
- Never `checkout -b` in a directory that holds another branch's edits, and never move edits with stash and pop.
- On Joey's Mac the main checkout has untracked preview files; always work in a worktree there.
- Branch name follows `.agents/skills/code-rules/SKILL.md` section 4. `scripts/guardrails/check-branch-name.sh` checks it.

## 2. Make the change

- Follow the code rules: no comments, files under 1000 lines, right folder.
- Before writing code for a fiddly part, list how it can break (see `.agents/skills/lock-fixed-bug/SKILL.md`, "Failure list first").
- When a value travels from settings to the screen, run `.agents/skills/feature-wiring-trace/SKILL.md`.

## 3. Pick and run the checks

- Use `.agents/skills/pre-push-check-selection/SKILL.md` to choose the smallest set for the paths you touched.
- Always run `scripts/guardrails/check-all.sh`. The pre-push hook runs it too once `git config core.hooksPath scripts/hooks` is set.
- Done when: every chosen check ran on the current tree and its result is written down with the tree hash. A check you could not run is written as "not run", never as passed.

## 4. Open the PR

- Push, then open a draft PR. The body says what changed, why, which checks ran on which tree, and any check that was not run.
- For a bug fix, paste the red output from the old code (see `.agents/skills/lock-fixed-bug/SKILL.md`).
- If the change adds or changes UI, attach a screenshot from a test build, never from `./build.sh`.
- Done when: CI has started on the head commit.

## 5. Drive it to green

```sh
.agents/skills/pr-delivery-loop/scripts/pr-status.sh <pr-number>
```

It prints check runs and commit statuses for the head commit plus how far the branch is behind main, and exits 0 only when `bad=[] pending=[] behind=0`.

- Read commit statuses as well as check runs. Some services report only as a status, and reading check runs alone once merged red deploys.
- A check that is missing is not a check that passed. If a job never started, find out why before merging.
- `behind>0` means CI ran against an old main. Update the branch (GitHub's update-branch or `git merge origin/main`, never a force push of rewritten history) and wait for the new run.
- In a cloud thread without `gh`, read the same three things with the GitHub tools: the PR's check runs, the combined status of the head commit, and the compare of base to head.
- Done when: `pr-status.sh` exits 0.

## 6. Merge

- Only Joey approves and merges. Ask once, in one message, with the exact action and target, for example "merge PR #57 into main".
- Run `pr-status.sh` again at the moment of merging. An admin bypass skips required checks, so this last run is the gate.
- Done when: merged, the worktree is removed (`git worktree remove ../MenuRunner-<short-description>`) and the branch is deleted.

## Several PRs at once

- Updating every open PR each time one merges reruns CI for all of them. First check whether an older green PR is about to merge, merge it, then update the rest once, and merge in PR number order.
- Put the mechanical refactors of one session (moves, renames, file splits) in one PR.

## Stacked PRs

- When the base PR is squash merged, the upper branch still carries the old commits. Run `git merge -X ours origin/main` on the upper branch.
- Never `git checkout --ours <file>`: it overwrites whole files and silently reverts other changes that reached main.
- After the merge compare the size with `git diff origin/main --stat | tail -1`; it should match the upper PR's own change.

## Releases

Releases are a separate flow: version bump PR, then `./make_dmg.sh` and `gh release create` on Joey's Mac. The tag must be `v` plus the version in `build.sh` and the DMG must be attached, or the in-app updater breaks.
