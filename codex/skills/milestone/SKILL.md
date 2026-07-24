---
name: milestone
description: 큰 업무를 여러 태스크로 쪼개 개발팀처럼 병렬 실행하는 워크플로우 — 계획(태스크 분할·파일계획·완료기준·그룹핑) → 승인 → 이슈·Milestone·브랜치·worktree → 그룹 병렬 실행(그룹 내 순차) → 그룹 PR 머지 전 검증 → 최종 PR. 작은 작업은 triage-fix/task-run으로 충분; work가 "크다"고 판단했거나 사용자가 /milestone 로 명시 호출할 때만.
argument-hint: <큰 업무 설명 | 노션·슬랙 링크>
---

# milestone — split a large piece of work and run it like a dev team

Take a large piece of work, **break it into small tasks, group related ones together (a group = one
developer), and run the groups in parallel while running tasks within a group sequentially** — all the
way to a final PR. Input: `$ARGUMENTS`

**Mental model — a dev team collaborating.** When in doubt, ask "what would a real dev team do?".

> Global skill. Project-specific values are read from `<repo>/.claude/triage.config.json` (run `/triage-init` if absent).
> In particular it uses `{milestone}` (base_branch·max_issues·max_parallel), `{models}`, `{branch_prefix}` (milestone/group).

## Core principles (role separation)

- **The controller (main) decides and delegates. The subs execute.**
  - Deciding, writing state files (plan.md etc.), assembling the values to hand off to subs = controller.
  - **git/gh execution (branch·worktree·PR·merge·close·cleanup) = `git-writer`.** **Running tests·full_verify = `qa`.**
    The controller does not directly run these heavy, side-effecting, raw-output-spewing operations. But reading/writing
    state files (plan.md·search-cache) and light local lookups (checking a SHA·branch name) are done by the controller directly —
    they're neither heavy enough to delegate nor do they pile up raw output.
- **Do not pile raw output (diffs·logs·full file contents) into the controller's context.** Sharing between agents goes through structured artifacts
  (result JSON·evidence packet·change-map·verify.log·search-cache).
- **If you get stuck or something breaks, file a new issue and move on.** Do not force your way through on guesswork. Only successful tasks get committed.
- **Each task is a proper loop.md loop** (the 5 stages of triage-fix/task-run), reused. The group branch is injected as the base branch, and because it's milestone mode the task loop creates no PR or issue branch.

## State files (centralized in the main repo — only the controller writes them, only code lives in the worktree)

`<repo>/.claude/loops/<milestone-slug>/` (add `.claude/loops/` to `.git/info/exclude`; delete after the milestone ends):
- `plan.md` — the whole milestone plan (a living document, updated as things are adjusted).
- `search-cache.json` — the search-result map (`keyword/symbol → [locations]` + `file→producing_sha` metadata). The controller merges serially.
- `groups/<group>/tasks/<issue#N>/{loop.md, change-map.md, verify.log}` — each task's artifacts (paths are per-group·per-issue, so no races).

Group workers work on **code only, in their own worktree**, and write state artifacts to the **main-repo absolute paths** above.

## Re-entry (compaction·session death·task addition)

A milestone is large enough that a single session may hit compaction or termination. Since all state is externalized, resume in a new session.
**Reconstruct where you are, in this order**: ① `plan.md` (tasks·groups·order·mode·issue#N) → ② presence of `groups/<group>/tasks/<issue#N>/`
artifacts → ③ git·gh state (group-branch commits·group PRs·integration/blocked issues·milestone HEAD).
**Judge completion by fact, not guesswork**: task done = the task's commit_sha exists on the group branch / group done = the group PR is merged /
blocked = a blocked issue (`[milestone:<slug>][task:<issue#N>]`) is open. **Do not re-run already-committed successful tasks**; resume from the incomplete·blocked ones.

**Task-addition re-entry** — when a new fix lands on an in-progress milestone (e.g. routed from `/work` stage 0):
① reconstruct where you are with the re-entry order above → ② **planner re-plans** — split the new fix into tasks, place them in an existing group or
a new group (re-run the ownership-matrix overlap check — if they overlap, run sequentially in the same group), update `plan.md` (preserving existing issue #Ns) →
③ **re-plan approval ✋** — show the re-plan result (new tasks·file plan·group placement·overlap report) to the user and proceed to ④ after approval
(the §guard "no issue creation before approval" applies equally. The execution mode inherits the mode [halt/bypass] locked in at the original ⑤, but
this approval is a plan approval like ⑤, so even under bypass it halts here) →
④ **git-writer creates the new issue** and pins #N in plan.md (the §⑥ convention) → ⑤ run it in that group via the **proper task loop** (§⑧),
then rejoin the group-PR → final-PR flow (if the final PR is already open, update it — **before updating, re-confirm ⑩'s debt-test audit and
full_verify** so an added task's tests don't slip into the final PR without an audit).

## Milestone stacking (a follow-up milestone on top of an unmerged one)

Applies when you start a follow-up milestone C while A (an unmerged milestone) waits to merge into main, or when you absorb another milestone B
into C (e.g. `/work` stage 0 multi-detection ⓒ). The base choice is locked in together at the §⑤ approval (no extra stop point added).
① **Start** — don't skip the flow; proceed normally from §① (via ⑤ approval). The only thing stacking changes is that at
  §⑦ branch creation, C's base (`{milestone.base_branch}`) becomes A's branch.
② **Absorbing B** — cherry-pick only the tasks worth keeping (one commit per task means task-level selection is possible; for a contiguous range use
  `git cherry-pick <start>..<end>` in one go. Merge+revert leaves an "added then removed" trace in history, so it isn't used).
  Include the selection (B tasks to keep/discard) in the §⑤ approval materials.
  Right after stacking, run **full_verify once** — A and B may each be green yet the combination can break, and without this gate tasks pile up on a broken base.
  The cherry-picked B tasks' tests are also **in scope for C's ⑩ debt audit** (they weren't audited on B's side).
③ **C's final-PR base = A's branch** (not main) — opening against main mixes all of A's changes into the diff, making review impossible.
  Once A merges into main and its branch is deleted, GitHub auto-retargets the C PR to main.
④ **Track A moving forward** — as A advances, periodically merge it into C (same principle as §⑨ re-verification). Skip it and C passes verification while stale.
⑤ **Convergence** — A → main first, then C → main. If they're effectively one body, merge C into A so the main gate converges onto A's single final PR.
  ⚠️ **Retarget warning**: before merging C, delete A's **remote** branch first (or manually change C's base to main) —
  retarget fires **only on deletion** of the base branch, so if you merge C before that, it goes into A instead of main (a real observed case).
⑥ **Cleaning up B** — close the GitHub Milestone (git-writer `op=close-milestone` — same procedure as §⑩ cleanup, including the open-issue check ✋), link surviving task issues to close on C, re-register unfinished tasks in C's `plan.md`,
  and clean up B's branches·worktrees·state folder. Cherry-picking changes the SHAs, so B-side completion tracking ("commit_sha exists on the group branch") breaks;
  skip this ledger cleanup and completion judgment goes wrong.

## Flow

### Stage 0 — load config
Same as triage-fix + secure `{milestone}`·`{models}`·`{branch_prefix.milestone|group}`. If `{models}` is set, spawn each subagent with that model.
**Serena activation is also identical to triage-fix stage 0** — if `serena=true`, main runs `mcp__serena__get_current_config` for an idempotent check, then
if needed `mcp__serena__activate_project <repo absolute path>` once (on failure, note it in one line and continue). The idempotent check isn't done once at stage 0 but
**on every entry into a search stage** (① right before delegating, on return after sequential worktree use) — the Serena server is
**one per session·one active-project slot·shared by all subs** (the basis for §⑧'s worker policy).

### ① Understand·split (issue-triage → planner)
- Right before delegating, do the **Serena idempotent check** (the stage-0 activation procedure) — this is a search-stage entry point. Pass issue-triage·planner
  the `serena` flag and the **repo absolute path**, and propagate the `serena fallback (reason)` note at the head of their reports into the user report.
- Understand the input (if it's a link, read the source). **Produce an evidence packet via issue-triage** (relevant file:line·symbols·suspected cause).
- **Delegate to planner**: pass the evidence packet + config (`convention_doc`·`tech_stack`·`serena`). The planner splits into tasks.

### ② File plan · ③ Grouping (planner)
- The planner writes each task's file plan + **completion criteria (as tests)**, groups related·dependent tasks into the **same group**, and
  uses an **ownership matrix** to mechanically check file overlap between groups (merge/warn on overlap). Factor out shared parts as a separate task only when it pays off.
- Record the planner output in `plan.md`. If the task count exceeds `{milestone.max_issues}`, confirm "split into multiple milestones / proceed?".

### ④ Order (planner)
- Decide the task order within a group (groups are independent of each other).

### ⑤ Approval ✋ (single stop point — plan + mode)
- Show the plan (tasks·file plan·completion criteria·groups + **overlap report**) to the user, and on the spot
  lock in the **execution mode [halt/bypass]** once. Don't create two stop points.
  - **Halt**: human approval per task + human review·merge of the group PR. **Always sequential** (parallelism off).
  - **Bypass**: auto-proceed; if the group PR is green, auto-merge (recorded in history). Parallel (§⑧). **Blocked ones become new issues.**
- **If an in-progress milestone is detected, fold the base choice into the same question**: `{default_branch}` (independent) /
  the in-progress `<A>` branch (stacking — §Milestone stacking applies). Under stacking, ⑦'s branch base and ⑩'s final-PR base become A's branch.
- Under either mode, **the final main PR (⑩) always halts** — a human merges.

### ⑥ Issue creation (git-writer)
- **Create the GitHub Milestone** (git-writer `op=create-milestone` — reuse if one with the same name exists).
- **Create an issue per task** (git-writer). **Pin the issue number (#N) as the task's stable key in plan.md** (preserved across re-planning).

### ⑦ Branch · worktree (git-writer)
- **Milestone branch** `{branch_prefix.milestone}<slug>` created off `{milestone.base_branch|default_branch}`
  (under stacking, off the A branch chosen at ⑤ — §Milestone stacking).
- **Group branch** `{branch_prefix.group}<slug>-<group>` created off the milestone branch.
- Under bypass+parallel, a **worktree** per group (`op=add-worktree`). Under halt mode (sequential) you can process sequentially without worktrees —
  in that case the Serena activate target is the **main repo** (stage-0 activation as-is — no worktree path switch).
- **Worktree dependency prep**: a fresh worktree has no `node_modules` etc., so tests·builds won't run out of the box.
  Right after creating a worktree, **install dependencies** (`{install_command}` if present, e.g. `pnpm install`). pnpm/yarn are usually cheap thanks to a
  shared store. Skip it if there's no install command or the stack doesn't need one (don't run it if it's not in config).

### ⑧ Execution (groups = parallel, within a group = sequential)
- **Parallel width `{milestone.max_parallel}`** (1=sequential under halt mode). Each group runs its tasks **sequentially** in its own worktree:
  - Each task = a **proper loop.md loop** (triage-fix=bug/task-run=feature). Hand off: loop.md path, planner plan,
    `base_branch=group branch`, config (`test_command`·`serena`·`models`…). Because it's milestone mode the task loop **creates no PR·issue branch**.
  - **Serena worker policy (per mode — state it in the worker spawn prompt)**: **parallel (bypass)** = workers **must not call Serena
    (grep/Glob/Read only)** — parallel workers contend over the single active-project slot, and a mistaken call returns results based on the main repo, causing
    confusion (workers have low search demand thanks to the planner plan+search-cache, so the actual loss is small). **Sequential (halt)** = only when a worktree was
    created, a worker may **activate its own worktree absolute path and then use Serena** (no concurrent user. No-worktree sequential stays on
    the main repo — §⑦) — be aware of the first-query warmup cost (tens of seconds/worktree).
    Under parallel, also **downgrade the `serena` in the config handed to workers to false** (double safety with the spawn-prompt prohibition —
    mechanically interlocks with the agent's "if serena=false, don't use serena tools" rule). Sequential keeps `serena=true`.
  - implementer implements + writes completion-criteria tests → generates a **change-map from the commit-candidate diff** → self-check (code-reviewer+policy-checker+qa).
  - **If the self-check is green, git-writer commits to the group branch.** On failure (blocked/max_iter/qa fail) → **don't commit + new issue** (dedup marker `[milestone:<slug>][task:<issue#N>]`, check for the same key before creating) + next task. Leave the failed task's original issue open.
  - Under halt mode, stop for the 4-stage approval per task.
  - **The task stage does no debt-test audit** — added tests are left as a regression net for later tasks, and the audit happens all at once at ⑩.
- **Search cache**: when a sub searches, it returns a cache_delta as result JSON → the controller merges serially into `search-cache.json`. On a file change (SHA), invalidate that file's entry.
  - **Hit metering**: subs also include `cache_hits`·`cache_misses` in their result JSON. The controller accumulates them into `search-cache.json`'s `_stats`
    (`total_hits`·`total_misses`·`hit_rate`) and records the hit rate in the ⑩ final-PR body (or log) — leaving data on whether the cache actually paid off.

### ⑨ Group PR + pre-merge verification (qa verifies · git-writer executes)
Once a group's tasks are all done:
- git-writer creates a **PR** from the group branch → milestone.
- **Create commit M**: git-writer `op=prepare-merge` (combine [latest milestone + group] in a temporary verification worktree) → **return M's SHA**.
  On a merge conflict it's failed here → handle as red below.
- **Pre-merge verification (qa)**: run `{loop.full_verify_command}` on the returned M (verification worktree), merge-queue style.
  This qa **only runs and judges tests** (not an audit), so it **can be spawned with a lower model (e.g. `{models.git-writer}`-tier) instead of `{models.qa}`** — saving tokens.
  - **green** → (halt=after human merge approval / bypass=immediately) git-writer `op=merge` fast-forward-only confirms **that same verified M as-is**
    as the milestone HEAD (not a re-merge) + cleans up the verification worktree. Then **post-merge cleanup**: `op=close-issue` only for successful task issues, `op=cleanup-branch`/`remove-worktree` for the group branch·worktree.
  - **red/conflict** → don't merge + clean up the verification worktree (`op=remove-worktree`) + create an **integration issue** + leave the group PR open + mark "unmerged" on the final PR.
- If another group merged first and the milestone advanced, rebuild M (re-run prepare-merge) and re-verify (repeat if stale).

### ⑩ Final PR ✋
- After all groups are merged or confirmed·marked unmerged, run the final `full_verify` (qa) once.
- **Debt-test audit (after the final full_verify is green · before creating the final PR)** — only for tests the whole milestone added,
  classify each by "if it breaks, is it a bug or a refactor?" (no proposing changes to existing tests); remove debt via a **cleanup commit**
  (milestone branch, git-writer) → re-confirm `full_verify` (if red, roll back the removal·keep it). If there are 0 debt items, proceed as-is.
- git-writer **opens the PR from the milestone branch → main and stops**
  (under stacking the base is the A branch, not main — §Milestone stacking ③. **Stacked-merge caution**: before merging C, delete A's **remote** branch
  first — §Milestone stacking ⑤ retarget warning). If any group is unmerged, make it a draft.
- PR body: completed tasks / incomplete·integration·unmerged list / tidied-up test record / summary of decisions made during execution.
- **Under either mode, a human does the main merge.** After the final PR merges (the user says "merged it/clean up" — same point as task-run stage 7,
  and the entry condition is identical to stage-7 item 1: **fact check** — confirm via fetch that the merge commit actually exists, abort if unmerged) **post-merge cleanup**:
  1. **Tagging** (when the repo has that convention) — if the milestone includes a version bump, tag·push the merge commit (git-writer `op=tag` — same as single-skill
     stage-7 item 2). For a stacked back-to-back merge (A→main then C→main), tag **in the order merged** (to prevent version inversion).
  2. **Close the GitHub Milestone** (git-writer `op=close-milestone`) — if the Milestone still has **open issues** (incomplete tasks·integration·blocked),
     confirm before closing ✋: ⓐ transfer the issues (unassign from the milestone or move to the next one) then close / ⓑ leave it open. If there are 0 open issues, close directly.
     **No auto-close — prevents unfinished work from being silently buried.**
  3. Delete `.claude/loops/<slug>/` — **only if item 2's close completed.** If you chose ⓑ (leave open), preserve `plan.md`
     (keeps `/work` re-detection·task-addition re-entry possible). The single-skill stage-7 sweep does not touch this folder while `plan.md` is present —
     cleanup is handled here.
  4. **Branch cleanup** — `op=cleanup-branch` the milestone branch·remaining group branches (merged only — same safety line as the stage-7 sweep).

## Event emission (optional — same emitter as §triage-fix)
Add parameters to the work-* events: `work_type=milestone`·`milestone=<slug>`·`scope=issue|milestone`·`group=<group>`.
Task completion is `scope=issue` (omit pr_url if before the group PR); the final PR is `scope=milestone`.

## Guards (do not violate)
- **No issue·branch·code creation before the ⑤ approval.** Plan only, then stop.
- **The controller must not run git/gh/tests directly** — delegate to git-writer/qa. Don't pile raw diffs·logs into context.
  (Reading·writing state files and light local lookups (SHA·branch name) are the exception — the controller does these directly.)
- **Blocked·integration breakage = new issue** (no forcing through). Only successful tasks get committed.
- **Pre-merge verification (qa) must be green to merge into the milestone.** Nothing broken gets into the milestone branch.
- **Main merge is never automatic** — always a human gate at the final PR.
- **Isolation via per-milestone folder·branch slug** — running multiple milestones at once is OK (no global lock needed).
