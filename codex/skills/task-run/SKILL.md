---
name: task-run
description: 일반 태스크(기능 추가·개선·리팩토링) 작업 — 요구 파악 → 알맞은 레포 결정 → 설계 → GitHub 이슈 생성 → 설계 승인 → 구현 루프(implementer 구현→검증→자가체크 반복)·PR. 규모 크면 plan mode 권유. 사용자가 /task-run(또는 /work 라우터) 로 호출할 때만.
argument-hint: <할 일 설명 | 노션·슬랙 링크>
---

# task-run — general tasks (feature/improvement) from grasp to PR

Handles general work like **new features, improvements, and refactors** rather than bugs. Input: `$ARGUMENTS`

Shares the same skeleton and config as `triage-fix` (bugs), but **centers on "design" instead of "root-cause analysis."**
For bugs the cause dictates the answer, but a general task has many possible approaches, so **design agreement comes first.**

> Global skill. Project-specific values are read from `<repo>/.claude/triage.config.json` (if absent, `/triage-init` recommended).

---

## Procedure

### Step 0 — Load config
Same as `triage-fix`. Read `triage.config.json` from the cwd (or the routed repo).
If absent, fall back (repo=git remote, default_branch=main, lint auto-detect, label_prefix="", loop.max_iterations=3, no loop.full_verify_command). Key values: `repo`, `default_branch`, `lint_command`, `test_command`, `convention_doc`, `tech_stack`, `commit_convention`, `branch_prefix`, `codeowners`, `serena`, `policy_docs`, `loop`, `models`.
**When spawning subagents, if `{models}` is set, launch them with the model from `config.models[<agent>]`** (absent → inherit — opt-in override).
**Serena activation is also the same as `triage-fix` step 0** — if `serena=true`, the main session checks via `mcp__serena__get_current_config`, then
runs `mcp__serena__activate_project <repo absolute path>` once if needed (on failure, note it in one line and continue). The idempotency check runs **only at two points: step 0 and just before the step 2
delegation** (in worktree mode, add a third point — **right after the step 5 worktree setup succeeds** — with the activate target = worktree absolute path.
Not a per-iteration recheck within the loop) — the Serena server allows 1 per session, 1 active-project slot, shared by all subagents.

### Step 1 — Read the requirement
From the input (text/Notion/Slack), grasp **what to build/change**. If ambiguous, ask the user a clarifying question (no guessing).

### Step 1.5 — Determine the repo (multi-repo routing)
Same as `triage-fix`. Confirm which repo the work targets (no auto-proceed on weak matches → confirm). **Only when the current cwd isn't that repo, run `cd <repo path>` alone once** to enter it (if already in that repo, don't cd) → that repo's config. After entering, run commands bare rather than wrapping them as `cd <path> && ...` (a compound cd triggers a permission prompt every time).

### Step 2 — Grasp related code and impact scope (delegate to issue-triage)
- Just before delegating, run the **Serena idempotency check** (the step 0 activation procedure) again — at the point of entering the exploration phase.
- Delegate to `issue-triage` (read-only). But instead of a bug, ask **"where do I need to touch to add this feature + what are the existing patterns + what's the impact scope."**
- Pass config (`serena` and the **repo absolute path**, `convention_doc`, `tech_stack`). Have it look first for existing similar implementations or reusable utilities (before writing new code).
  The `serena fallback (reason)` note at the head of the report is propagated verbatim to the user report (don't swallow it silently).

### Step 3 — Design (plan mode auto-triggered by scale)
- **Small task** (one or two files, an obvious implementation): put together a simple design (what, where, how).
- **Large task** (multiple files, architectural decisions, several approaches): **recommend plan mode** — "This looks like it needs design; shall we go to plan mode?" and, on agreement, write the plan via EnterPlanMode.
- The design reflects reuse of existing patterns and the config's tech_stack and architecture.

### Step 4 — Create GitHub issue + design approval ✋ (mandatory stop point)
- **Main session writes**: finalize the body, title (`{label_prefix}` + original), and labels (`enhancement`/`feature`, omit if absent) using the **issue template** below.
- **Delegate to git-writer** to create it: pass only the finalized values (`repo={repo}`, `issue_title`, `issue_body`, `labels`), and it
  runs `gh issue create` and **returns only the URL** (verbose output stays trapped in the subagent). Capture the returned URL (§git-writer delegation).
- **Show the design and get approval** (this step matters more than for bugs — because the direction can diverge):
  > "Created issue #N: <full URL>
  >  repo: {repo} / base: {default_branch}
  >  On approval I'll proceed with the implementation loop (implementer implements → lint·tests → self-check, up to {loop.max_iterations} times).
  >  This is the design — shall I implement it this way?"
- No code changes before explicit approval. If the direction changes, apply it and re-confirm.
- ⚠️ **An answer to a scope/approach question is NOT "approval."** Even if you asked about scope/approach in steps 1·3 and got an answer,
  that's only a *design agreement*. **You must get a separate explicit OK to this step 4 "shall I implement it this way?"** before going
  to step 5. Don't mistake a mid-question answer for approval and jump straight in.

### Step 5 — Branch + implementation loop 🔁
The structure and loop.md template are **the same as `triage-fix` step 5** (including base-branch parameterization) — the main session is only the loop controller
(no direct implementation); implementation is done each iteration by the `implementer` subagent. task-run specifics:
- **Setup**: base = `{base_branch}` if injected (milestone mode = group branch), otherwise `{default_branch}`. A single task
  branches off that base as `{branch_prefix.feat}<slug>` (default `feat/`, an appropriate prefix if it's a refactor). Milestone mode only stacks
  commits on the group branch and creates no issue branch or PR (same as the triage-fix step 5·6 milestone guards).
  If config `worktree=true`, **apply the same "worktree setup" branch as triage-fix step 5** (**milestone mode skips this branch too** —
  worktree is prepared per-group by `/milestone` ⑦, same as the triage-fix guard) — create a branch+worktree at `<repo>/.claude/worktrees/<issue number>`
  (git-writer `op=add-worktree`) → if `{milestone.install_command}` is set, install dependencies →
  pass the worktree absolute path as cwd to implementer and the self-checks (on creation failure, fall back to the current path + a one-line note;
  the Serena activation path is also the worktree — the safety premise is **within a single session**; returning to the main repo is handled by the existing idempotency check.
  Default false keeps the current behavior).
  Create `<repo>/.claude/loops/<issue number>/loop.md` — copy the completion criteria verbatim from the issue's **"✅ Completion criteria"** checklist
  (no edits during the loop). **In "Related locations," directly copy the change scope from the issue's "📐 Design" + the file:line originals
  returned by issue-triage in step 2** (the issue body is a summary and may be clipped, so put in the full issue-triage return —
  the main session already has it, so zero extra tokens, and it prevents implementer re-exploration). Add `.claude/loops/`·`.claude/worktrees/` to `.git/info/exclude` (info/exclude is shared across worktrees, so once is enough).
  Once setup is done, **emit an event**: `work-started` — args `branch=<branch name> title="<issue title>" issue_url=<full issue URL>` (§event emission).
- **Loop (up to `{loop.max_iterations}` times, default 3):**
  1. Delegate to `implementer` — loop.md path + this iteration's directive (iteration 1 = the **design** approved in step 4;
     from iteration 2 = the prior findings) + config (`convention_doc`·`tech_stack`·`lint_command`·`test_command`·`serena`)
     + **`change_map_path`** (`change-map.md` in the loop.md folder). Spell out in the directive to **follow existing patterns and conventions** (no over-abstracting).
     Have it **write tests satisfying the completion criteria**, pass lint, report + **leave the change-map at that path once** (running/judging tests is qa's job).
  2. Self-check — `policy-checker`+`code-reviewer`+`qa` **3 in parallel** (read-only). Pass `{policy_docs}`·`{convention_doc}`·`{tech_stack}`·`{serena}`,
     and to qa pass **the completion criteria (loop.md) + `{test_command}`** (test audit·run·judgment, verify.log). If `{models}` is set, spawn each with its model.
     **Pass the list of changed-file paths + `change_map_path`** (the "Changed files" field from the implementer report + the change-map path).
     The 3 axes **read the change-map first and check the originals only at suspect spots**. **Do not put the full `git diff`
     in the prompt** — if a diff is needed, the checker opens the file itself via its own Read (saves context).
     **Iteration 1 = full inspection, from iteration 2 = re-verify mode** — pass only the prior findings + this iteration's **changed-file paths** (+ the updated change_map_path)
     to look at "whether findings are resolved + new violations in the changes" only (no full recheck). A qa failure (test failure/inadequacy) is also REQUEST_CHANGES.
     The `serena fallback (reason)` note in the subagent report is propagated to the user report.
  3. Judgment — ❌violation (policy·code)·qa failure = **REQUEST_CHANGES** (record findings in loop.md, then re-delegate) / even if only ⚠️, it may be escalated to ❌
     if it's a real regression, data loss, or security exposure (record the reason in loop.md) / no ❌ = **APPROVE** —
     if `{loop.full_verify_command}` is set, run it once here (full build, etc.; on failure REQUEST_CHANGES into
     the next iteration), and on pass record ⚠️ in the PR self-check and go to step 5.5 / implementer **stuck** = halt·report.
     Right after recording the judgment in loop.md, **emit an event**: `iteration-completed` — args
     `iteration=<iteration> verdict=<approve|request_changes|blocked>` (§event emission).
- On max exhaustion, halt·report without commit or PR (keep the WIP branch). **No commit·push inside the loop.**
- When the loop halts (stuck·max exhaustion), before reporting **emit an event**: `work-stopped` — arg `reason=<blocked|max-iterations>` (§event emission).

### Step 5.5 — Debt-test audit (after APPROVE · before commit)
> **Milestone mode skips this step too** — no audit during a task; it's done in bulk at `/milestone` ⑩.

To keep debt tests out of main, audit **only the tests this loop added** (no removal proposals for existing ones).
- **fast-path**: if 0 tests were added, go straight to step 6 with no classification.
- **Classification**: "If it breaks, is it a **bug** or a **refactor**?" — behavior-spec verification = asset (keep); coupling to implementation details, tautological, or duplicate = debt (remove).
- **Procedure**: classify (reuse the qa audit result or the main session's judgment) → remove debt (implementer) → re-run the remaining tests **once**, confirm green (qa) → step 6. If red, roll back·keep.
- **If 0 debt, go straight to step 6.** Record the removal log (file:test name + reason) in the PR self-check.

### Step 6 — Commit + PR (only after APPROVE · delegate to git-writer)
> **Milestone mode skips this step** — a task only commits to the group branch; the group and final PRs are created by `/milestone`. The below is for single tasks only.

**The main session judges·writes** and git-writer executes.
- **Main session writes**: the commit message (**`{commit_convention}` takes top priority**; if absent, Conventional Commits — usually `feat:`/`refactor:`/`chore:`, **no Co-Authored-By**), PR title/body (`Closes #N`), reviewer list (based on `{codeowners}`, author excluded, empty list if absent), staging directive (usually `all`).
- **Delegate to git-writer**: pass the finalized values above + `repo={repo}`·`branch`·`base_branch={base_branch|default_branch}` (single = `{default_branch}`).
  If the step 5 worktree setup **succeeded**, also pass `work_path=<worktree absolute path>` — do add→commit→push in that path (on the creation-failure fallback, the current path).
  git-writer runs `add→commit→push→gh pr create` and **returns only the PR URL**. The author stays as the current git config.
  git-writer reads no log/diff/code (the main session handed over everything finalized). On a failure report, no forced retry — go to the user.
- Report the returned issue·PR **full URLs as clickable**. If it was worktree mode, add a **one-line cleanup note** ("after merge, say 'merged' for
  step 7 cleanup" or confirm `op=remove-worktree` immediately — if left uncleaned, hundreds of MB accumulate per issue, and since it's info/exclude it doesn't even show in status).
  After the PR, delete `.claude/loops/<issue number>/` (single-use).
- **Emit an event**: `work-finished` — args `pr_url=<full PR URL> iterations=<total iterations>` (§event emission).

### Step 7 (optional) — Post-merge cleanup
Run only when, **after the PR is merged**, the user requests it with something like "merged / clean up" (no auto-entry).
1. **Verify the fact** — via fetch, confirm the merge commit actually exists on `{default_branch}` (no guessing). If unmerged, say so and stop.
   **Milestone detection**: a `.claude/loops/` folder containing a `plan.md` is a milestone — exclude it from the sweep below, and
   route its cleanup through the `/milestone` ⑩ "post-merge cleanup" procedure (so the sweep doesn't bypass the Milestone-close confirmation ✋).
2. **Tagging** (when the repo has a convention) — if it's a version-bump PR, tag·push the merge commit (git-writer `op=tag`). Omit if there's no convention.
3. **Local cleanup (sweep · git-writer)** — not just this task's, but **everything cleanable**, in the order **remove worktree →
   delete branch** (a branch checked out by a worktree is refused by `-d`):
   remove all prunable worktrees; for single-task worktrees (`.claude/worktrees/<issue number>`), explicitly remove **only those of closed issues·merged branches**
   via `op=remove-worktree` (don't touch worktrees of in-progress parallel work even if clean),
   then delete all merged local branches (`-d` only — unmerged ones are auto-protected because git refuses them; report the refused list),
   report only if any worktree·branch has uncommitted changes, and delete all zombie `.claude/loops/` folders of closed issues
   (excluding milestone folders with `plan.md` — the detection in step 1).

No test audit here — it already finished before the merge in step 5.5.

---

## git-writer delegation (write execution)
Same as `triage-fix`. The **execution** of issue creation (step 4) and commit+PR (step 6) is done by the `git-writer` subagent —
it keeps `git log`/`diff`/`gh` output out of the main session and trapped in the subagent to **save context**.
- **Main session judges·writes** (commit message·PR body·reviewers·staging decisions), **git-writer only executes**.
  git-writer reads no code·log·diff — because the main session handed over the finalized values.
- Values passed: (issue) `repo`·`issue_title`·`issue_body`·`labels` / (PR) `repo`·`branch`·`base_branch`·`commit_message`·`pr_title`·`pr_body`·`reviewers`·`stage`. Value received: URL only.

## GitHub account (reference)
dobiflow **trusts the currently logged-in gh account and the current git config as-is**.
Account switching·multi-account is handled outside dobiflow (e.g. `gitto`) — git-writer runs plainly with no auth injection.

## Issue template (step 4)

```markdown
## 🎯 목표
<무엇을 만들/바꾸는지 1~3줄>

## 📐 설계
- 접근: <어떻게 — 핵심 방식>
- 변경 범위: `path/...` (재사용할 기존 패턴/유틸이 있으면 명시)
- (대안 있었으면) 왜 이 방식인지 한 줄

## ✅ 완료 기준
- [ ] <이게 되면 끝 — 가능하면 "테스트: <검증 방법>" 형태로. implementer가 테스트 짜고 qa가 실행·판정>
- (테스트로 못 담는 주관·시각 항목은 "PR 셀프체크:"로 표시해 사람이 최종 PR에서 확인)

## 출처
- 원본: <링크 또는 텍스트>

---
🤖 자동 생성됨
```

## PR template (step 6)
```markdown
## 바뀐 점
<이 PR로 무엇이 생기/달라지는지, 사용자/화면 관점>

## 배경
Closes #<이슈번호>
<왜 필요한지 1~2줄>

## 작업 내용
- <핵심 변경, `file:line`>

## 셀프체크
- 루프: <N>회차에 APPROVE
- 정책: <policy-checker 요약>
- 코드: <code-reviewer 요약>
- 테스트: <qa 요약 — 완료기준 테스트 통과, 실행 명령>
- 정리된 테스트: <5.5단계 제거 내역(파일:테스트명+사유) 또는 "없음">

## 리뷰 포인트
- [ ] <확인할 것>

---
🤖 자동 생성됨
```

> Keep the wording in natural Korean.

---

## Event emission (optional — for external collection·notification)

Same structure as `triage-fix`. At each designated point in steps 5·6, run the one line below:

```
~/.dobiflow/bin/dobiflow-emit <event> skill=task-run repo={repo} issue=<issue number> <point-specific extra args>
```

- 4 events: `work-started` (loop entry) → `iteration-completed` (each iteration's judgment) →
  `work-finished` (PR created) or `work-stopped` (halt on stuck·max exhaustion).
- **Check existence once before loop entry**: `test -x ~/.dobiflow/bin/dobiflow-emit` — if absent (not installed),
  silently skip all emissions for this task.
- **It's an add-on** — even if an emission fails, ignore it and continue the actual work. No retry·debugging·separate report.

---

## Tone
User-facing **progress reports·stop points·completion notices** use the **Dobby tone**.
The rules·per-step examples·scope (tone not applied to issue/PR bodies·loop.md·subagent prompts) follow
`references/dobi-persona.md` (read as needed).
The tone is expression only — it does not change the guards·stop points·delegation rules below.

## Guards
- **No code changes before the step 4 design approval.** Only up to issue creation is OK.
- ⚠️ **Even if a direct command like "fix it/build it" is in the input, do not skip issue creation·design approval.** A direct command = "please handle it," not "skip the procedure."
- **No direct implementation by the main session in step 5** — all implementation·edits are delegated to implementer. The main session only judges·records the loop.
- **No commit·push inside the loop** — once after APPROVE. On max exhaustion·stuck, halt·report without a commit.
- **Reading/grasping is delegated to issue-triage.** Find existing patterns first and reuse them (before writing new code).
- **Commits follow the project rule (`commit_convention`) first. No Co-Authored-By.**
- **Recommend plan mode for large tasks** — don't enter a large implementation without design agreement.
- **Misfire prevention** — re-confirm the target repo just before writing. Trust the current gh login state for the account (multi-account is outside dobiflow).
- No auto-proceed on weak routing matches.
- Everything runs locally (no GitHub Actions).
