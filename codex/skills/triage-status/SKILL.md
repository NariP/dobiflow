---
name: triage-status
description: triage 작업 현황 조회 — 열린 이슈와 진행 중 PR을 한눈에. 조회 전용(수정 안 함). 사용자가 /triage-status 로 명시 호출할 때만.
---

# triage-status — triage work status overview (general-purpose)

A **read-only** skill that shows everything being handled via `/triage-fix` at a glance.
It does not fix code or create issues/PRs. Use it to see what is open and what is unfinished.

> Global skill. Repo and prefixes are read from `.claude/triage.config.json` in the cwd.

## Behavior

0. **Load config**: read `.claude/triage.config.json` in the cwd to obtain `{repo}`,
   `{label_prefix}`, `{branch_prefix}`. If absent, `{repo}` = auto-detected via
   `git remote get-url origin`, and `{label_prefix}` = `""`.
1. Query **open issues**:
   ```bash
   gh issue list --repo {repo} --state open --limit 20 \
     --json number,title,labels,url
   ```
2. Query **open PRs**:
   ```bash
   gh pr list --repo {repo} --state open --limit 20 \
     --json number,title,headRefName,url
   ```
3. Combine both and display in the format below. Prioritize showing
   **issues with the `{label_prefix}` prefix** (all issues if empty) and
   **PRs on `{branch_prefix}` branches** (default `fix/`, `feat/`) as triage outputs.

## Output format

```
## 🐞 열린 이슈 (N개)
- #N <제목>  (<라벨>)
  <전체 issue URL>
- ...

## 🔀 진행 중 PR (N개)
- #N <제목>  [<브랜치명>]
  <전체 PR URL>
- ...

## 💡 이어가기
- Point out "unfinished things" (an issue with no linked PR, or a PR that isn't merged).
- To continue a specific task: check out the relevant branch (`git checkout <branch>`),
  or for a new fix, run `/triage-fix` again.
```

## Guards

- **Read-only** — `gh issue create` / `gh pr create` / editing code are strictly forbidden.
- Always display URLs in full, clickable form (never just `#N`).
- Continuing a "conversation session" itself is a built-in Claude Code feature
  (`claude --resume` / `--continue`), not this skill — if the user asks about resuming a
  session, point them to that.
