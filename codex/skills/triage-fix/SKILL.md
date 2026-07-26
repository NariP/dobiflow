---
name: triage-fix
description: 이슈(노션/슬랙 링크·텍스트) → 알맞은 레포 결정 → 원인 파악 → GitHub 이슈 생성 → 승인 → 구현 루프(implementer 구현→검증→자가체크 반복)·PR. 사용자가 /triage-fix 로 명시 호출할 때만 실행 (수동 전용).
argument-hint: <노션링크 | 슬랙링크 | 이슈 설명 텍스트>
---

# triage-fix — From issue triage to PR (general-purpose)

A workflow that takes the given issue, **files a GitHub issue in the right repo**, and — after
user approval — **cuts a branch, fixes it, and opens a PR**. Input: `$ARGUMENTS`

The input can be a Notion link, a Slack link, or plain text — anything. Read the source to understand it.

> This skill is **global**. Project-specific values (repo, policy docs, lint, etc.) are read from
> each project's `.claude/triage.config.json`. Generate the config file with `/triage-init`.

---

## Sequence (follow this order)

### Step 0 — Load config
- Once the target repo is decided, read that repo's `<repo>/.claude/triage.config.json`.
- If the repo isn't decided yet, decide it in Step 1.5 (repo selection) after Step 1. If the current cwd is the work target, you may read cwd's config first.
- **If there's no config, run in fallback mode** plus a one-line "no config — `/triage-init` recommended" notice:
  - `repo` = auto-detect via `git remote get-url origin`
  - `default_branch` = `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (falls back to `main`)
  - `lint_command` = detect from package.json scripts (`lint:fix`>`lint`>`format`), omit if none
  - `policy_docs` = `.claude/docs/*.md` glob (empty list if none)
  - `label_prefix` = `""` (no prefix)
  - `loop.max_iterations` = unset → `3` (max implementation-loop iterations)
  - `loop.full_verify_command` = unset → none (skip heavy verification at APPROVE — loop verification is lint/test only)
- Later steps use config values such as `{repo}`, `{default_branch}`, `{lint_command}`, `{test_command}`, `{policy_docs}`,
  `{label_prefix}`, `{branch_prefix}`, `{bug_label}`, `{codeowners}`,
  `{serena}`, `{convention_doc}`, `{tech_stack}`, `{loop}`, `{models}`.
- **Model override when spawning subagents:** if `{models}` is set, spawn each subagent with the model from
  `config.models[<agent>]` (e.g. `models.implementer`, `models.qa`). If unset, inherit the session model (current behavior).
- **Serena activation (`serena=true` · main does it directly):** check the active project with
  `mcp__serena__get_current_config`, and if it differs from the current repo or is inactive, run
  `mcp__serena__activate_project <repo absolute path>` once. On failure, tell the user in one line and
  continue (subagents naturally fall back to grep). This idempotent check runs **only at two points —
  Step 0 and right before the Step 2 delegation** (in worktree mode, add a third: **right after Step 5
  worktree prep succeeds** — activation target = worktree absolute path. Not a per-loop recheck) — this
  guarantees return after sequential worktree use (the check call is cheap).
  The Serena server is **one per session · one active-project slot · shared by all subagents**, so once
  main turns it on, every subagent uses it.

### Step 1 — Read the source
- **Notion link** (`notion.so` / `notion.com`): fetch page content via `mcp__claude_ai_Notion__notion-fetch`.
- **Slack link** (`slack.com/archives/...`): read the message/thread via Slack MCP.
- **Text only**: use it as-is as the issue description.
- If it's a link but reading fails, ask the user to paste the content and stop (no guessing).

### Step 1.5 — Repo selection (multi-repo routing)
Decide **which repo the issue belongs to**. Skippable if cwd is already the obvious target.
- **Candidate sources**:
  1. (primary) Local scan — the git remotes (`owner/name`) of cloned repos (subdirectories of the work root) +
     the `repo`/`keywords` in each repo's `.claude/triage.config.json`.
  2. (supplement) If there's an org repo-catalog MCP, use its descriptions. For un-cloned repos, note "clone needed".
- **Matching**: issue clues (screen name, feature, domain keywords) ↔ candidates' keywords/descriptions/directory names.
- **No auto-proceed on a weak match** — present the top 2–3 candidates via `AskUserQuestion` and get confirmation.
- Once confirmed, **only when the current cwd is not that repo, run `cd <repo path>` on its own, once** to enter it (to load that repo's config — `cd` doesn't change Serena's active project, so Serena alignment is handled by the Step 0 activation procedure). **If you're already inside that repo, don't cd.** Since cwd persists across later Bash calls, don't wrap post-entry commands in `cd <path> && ...` — just run **the command alone** (a `cd X && cmd` compound command triggers a permission prompt every time).
- **If the repo isn't cloned**, work is impossible → advise "clone and retry" (no arbitrary cloning).

### Step 2 — Code root-cause analysis (delegate to issue-triage)
- Right before delegating, run the **Serena idempotent check** (Step 0 activation procedure) again — this is the entry into the exploration phase.
- Delegate to the `issue-triage` subagent. Read-only investigation only (no code changes).
- **Pass config values too**: `serena` (whether LSP is available) and the **repo absolute path**, `convention_doc`, `policy_docs`,
  and clues such as screen paths / labels / component names. If `serena=false`, tell it to use grep only.
- What you'll get back: relevant file:line, data flow, cause hypothesis, fix points.
  If the report leads with a `serena fallback (reason)` note, **propagate it verbatim to the user report** (don't silently swallow it).

### Step 3 — Create the GitHub issue (create it first · delegate to git-writer)
- **Main writes it**: fill the body with the **issue template** below, and finalize the title (original + `{label_prefix}`,
  no prefix if empty) and labels (`{bug_label}`, default `bug`).
- **Delegate execution to the git-writer subagent.** Pass only the finished values —
  `repo={repo}`, `issue_title`, `issue_body` (finished), `labels`.
  git-writer only runs `gh issue create` and **returns the full URL** (the verbose gh output stays trapped in the subagent).
- Capture the returned issue URL as-is.
- **Why delegate**: to keep the main session from receiving gh output directly, saving context. git-writer
  doesn't read code/log/diff — it only executes the values it's given (§git-writer delegation).

### Step 4 — Get approval ✋ (mandatory stop-point)
- **Show the created issue content (root-cause analysis + fix plan) to the user** and ask.
- **When reporting the created issue, spell out the full URL returned by `gh` as a clickable link** (don't use just `#N`).
- **Confirm the repo and base branch together on one screen** (to prevent mis-targeting). Example:
  > "Made issue #N: <full URL>
  >  repo: {repo} / base: {default_branch}
  >  If you approve, I'll proceed to the implementation loop (implementer implements → lint/test → self-check, up to {loop.max_iterations} rounds).
  >  Shall I fix it this way and open a PR?"
- **Never touch code** until the user explicitly says **OK / 진행 / go ahead**.

### Step 5 — Branch + implementation loop 🔁

In this step the main session **does not implement directly** — it only acts as the loop controller
(iteration management, verdicts, loop.md updates). Implementation is done by the `implementer` subagent each round.

**Prep (once, before entering the loop):**
- **Decide the base branch**: if `{base_branch}` is injected, branch from that; otherwise branch from `{default_branch}`.
  - **Single task (default)**: no `{base_branch}` → a new branch `{branch_prefix.fix}<short-english-slug>` off `{default_branch}` (default `fix/`).
  - **Milestone mode**: the caller (/milestone) injects `{base_branch}=group branch` → work on top of that group branch (tasks
    stack as commits on the group branch). In this case, **don't create a new issue branch or PR** (see the Step 6 milestone guard).
- **Worktree prep (only when config `worktree=true` — if the default false, skip this item; unchanged behavior)**:
  > **In milestone mode, skip this item too** — worktrees are created per-group by `/milestone` ⑦. If the task loop
  > runs `op=add-worktree` again it collides with the group branch, and the failure fallback breaks group isolation. The below is **single-task only**.

  So that a single task doesn't occupy the main working tree either, instead of checking out the branch decided above into the main working tree,
  use git-writer `op=add-worktree` to create the branch+worktree at `<repo>/.claude/worktrees/<issue-number>`.
  Right after creation, if `{milestone.install_command}` exists, install dependencies in that worktree (reusing the milestone ⑦ "worktree dependency prep" convention).
  Then, when spawning the implementer and the three self-check axes, **pass the worktree absolute path as the work path (cwd)**, and
  run the Step 6 commit from that path too (git-writer `work_path`). State files (`.claude/loops/<issue-number>/`) stay
  **centralized in the main repo** per the milestone convention.
  **On creation failure (disk, permissions, etc.)**, fall back to the current approach (branch in the main working tree) and tell the user in one line.
  **Serena** (`serena=true`): the target path of the Step 0 activation procedure becomes the **worktree absolute path** — a single task
  has no concurrent users, so it's safe (the safety premise is **within one session** — one server per session, one active slot), and since the idempotent check is path-based
  it's handled naturally by the same procedure. Each worktree has a separate index, so a **first-query warmup** occurs, and after the work the
  return to the main repo needs no separate procedure — the **existing idempotent check handles it**.
- **Create loop.md**: `<repo>/.claude/loops/<issue-number>/loop.md` — per the **loop.md template** below.
  Copy the completion criteria straight from the issue's "fix plan" / "expected behavior" (**no edits during the loop**).
  **Copy "relevant locations" verbatim from the relevant-locations/flow source that Step 2 issue-triage returned** — since the issue body (🔍 root-cause analysis)
  is a user-facing summary and file:lines may be trimmed, put the **full issue-triage return** into loop.md (main already has it, so
  0 extra tokens). This is the handoff that keeps the implementer from re-exploring — the more detail, the less re-exploration.
- Add one line each to `.git/info/exclude` so `.claude/loops/` and `.claude/worktrees/` aren't committed
  (skip if already present — info/exclude is shared across worktrees, so once is enough).
- **Emit event**: `work-started` — args `branch=<branch-name> title="<issue title>" issue_url=<issue full URL>` (§emit events).

**Loop (up to `{loop.max_iterations}` rounds, default 3):**
1. **Implement — delegate to the `implementer` subagent.** Pass: the loop.md path, this round's instruction
   (round 1 = the issue's fix plan; from round 2 = the previous round's REQUEST_CHANGES findings),
   config (`convention_doc`·`tech_stack`·`lint_command`·`test_command`·`serena`),
   and **`change_map_path`** (the `change-map.md` in the loop.md folder). The implementer implements with minimal edits and
   **writes a test that satisfies the completion criteria**, then makes **lint pass** before reporting, and **leaves a change-map at that path once**
   (per-file change intent · risk · test linkage — read first by the three self-check axes). **Running tests and judging pass/fail is qa's job** (self-check below). If it can't be solved, report "blocked" (no done-report in a failing state).
2. **Self-check — three subagents in parallel (read-only).** **Pass the list of changed-file paths + `change_map_path`**
   (the "changed files" field of the implementer's report + the change-map path). The three axes **read the change-map first and only open the originals at suspect spots**.
   **Don't put the full `git diff` in the prompt** — if a diff is needed,
   the checker opens the current state of that file with its own Read (context saving).
   - **`policy-checker`** — domain policy violations. **Pass the `{policy_docs}` list as an arg** (if empty, "no policy docs" → pass).
   - **`code-reviewer`** — general code quality. **Pass `{convention_doc}`+`{tech_stack}`** (if absent, general best practices).
   - **`qa`** — completion-criteria test verification. **Pass the completion criteria (loop.md) + `{test_command}`.** Audits whether the tests
     actually verify the criteria and **runs them to judge pass/fail** (verify.log). Hollow, happy-path-only, or missing edges = fail.
   - All three also receive the `{serena}` value (grep fallback if false). If `{models}` is set, spawn each with its model.
     Propagate any `serena fallback (reason)` note in a subagent's report to the user report.
   - **Round 1 = full check** (all changed files of this task). **From round 2 = re-verify mode** — no full recheck.
     Pass: ① the previous findings list ② the **changed-file paths** this round's implementer reported (+ the updated `change_map_path`).
     Only two check questions — "were the findings resolved + did the change create a new violation" (the full pass was already done in round 1).
3. **Verdict (main session):**
   - implementer reports **blocked** → stop the loop immediately, report to the user (no commit/PR).
   - ❌ **violations present (policy/code) or qa fail (test failure · weak tests)** → **REQUEST_CHANGES**:
     record the findings in the loop.md iteration log and go to the next round. (If qa fails for "weak tests", the implementer strengthens the tests.)
   - Even if there are only ⚠️, if judged to be **real regression, data loss, or security exposure**, you may promote it to ❌ and REQUEST_CHANGES
     — record the promotion reason in loop.md (a safety net for when a checker classified severity too low).
   - No ❌ (only ⚠️/💡) → **APPROVE**: if `{loop.full_verify_command}` exists, **run it once here**
     (heavy verification like a full build — not every round, only at APPROVE). If it fails, take the failure
     as findings and REQUEST_CHANGES into the next round. On pass (or no command), summarize the ⚠️ for the PR "## self-check"
     and end the loop → Step 5.5.
   - Right after recording the verdict in loop.md, **emit event**: `iteration-completed` — args
     `iteration=<round> verdict=<approve|request_changes|blocked>` (§emit events).

- **On max exhaustion**: stop without commit/PR. Keep the WIP branch, and report to the user with the last findings +
  what's stuck (continue / change direction / check yourself is the user's call).
- **On loop stop** (blocked · max exhausted): before reporting, **emit event**: `work-stopped` — args
  `reason=<blocked|max-iterations>` (§emit events).
- A small fix (one or two files, obvious) usually **ends in one round at APPROVE** — the structure is the same, there just aren't repeats.
- **No commit/push inside the loop** — once, in Step 6 after APPROVE.
- **Where a backend fix is needed, don't work around it arbitrarily in the frontend** — note "backend needed" in the issue/PR.

### Step 5.5 — Debt-test audit (after APPROVE · before commit)
> **In milestone mode, skip this step too** — don't audit during tasks; do it in bulk at `/milestone` ⑩.

To keep debt tests out of main, audit **only the tests this loop added** (proposing removal of existing ones is forbidden too).
- **fast-path**: if 0 tests were added, go straight to Step 6 with no classification.
- **Judgment**: "if it breaks, is it a **bug** or a **refactor**?" — behavior-spec verification = asset (keep); coupling to implementation details, tautological, or duplicate = debt (remove).
- **Procedure**: classify (reuse qa's audit result or main's judgment) → remove debt (implementer) → re-run the remaining tests **once**, confirm green (qa) → Step 6. If red, roll back and keep.
- **If 0 debt, go to Step 6 as-is.** Record the removal list (file:test-name + reason) in the PR self-check.

### Step 6 — Commit + PR (only after APPROVE · delegate to git-writer)
> **In milestone mode, skip this step.** Tasks only stack commits on the group branch (no PR or issue branch created);
> the group PR and final PR are made per-group by `/milestone`. The below is **single-task (non-milestone)** only.

Main finishes all judging/writing, and delegates execution to git-writer.

**What main writes/decides (finished values to hand off):**
- **Commit message** — **follow `{commit_convention}` (that project's rule) first** and let main write it.
  If config has `commit_convention`, use its rule/examples format (prefix, language, emoji, etc.).
  If absent, fall back to Conventional Commits. **In any case, no `Co-Authored-By` trailer.**
- **PR title/body** — the title matches the commit title. The body follows the **PR template** below (`Closes #N` + original Notion/Slack link).
- **Reviewer list** — if `{codeowners}` is a path, from the matching code owners **exclude the author themselves** → the remaining people.
  If no one remains or `{codeowners}` is false, an empty list (omit reviewers).
- **Staging instruction** — usually `all` (all changes on the work branch). If only specific files, the file list.

**Delegate execution to git-writer:** hand off the finished values above + `repo={repo}` `branch=<work branch>` `base_branch={base_branch|default_branch}` (single=`{default_branch}`).
git-writer runs `git add → commit → push → gh pr create` and **returns only the PR URL**.
- If the Step 5 worktree prep **succeeded**, also pass `work_path=<worktree absolute path>` (on creation-failure
  fallback, the current path as-is) — git-writer runs add→commit→push from that path (PR creation is the same).
- The author stays exactly as the current git config (dobiflow doesn't touch the account). No auth injection.
- **git-writer doesn't read log/diff/code** — because main already finished and handed off the commit message and PR body.
- If you get a failure (permissions/conflict) report, report to the user without forcing a retry.

- **Report the returned full PR URL as a clickable link.** In the wrap-up, spell out **both** the issue URL and the PR URL.
- If it was worktree mode (Step 5 prep succeeded), a **one-line cleanup notice** — "after merge, say 'merged' for the Step 7 cleanup", or if you want, an immediate
  `op=remove-worktree` confirmation (if Step 7 isn't called, hundreds of MB accumulate per issue — being in info/exclude, it doesn't even show in status).
- After creating the PR, **delete** `.claude/loops/<issue-number>/` (loop.md is single-use — the record stays in the issue/PR).
- **Emit event**: `work-finished` — args `pr_url=<PR full URL> iterations=<total rounds>` (§emit events).

> **Body humanizing is optional — off by default for short PRs.** Only for long reports/docs, run `/humanize` manually.

### Step 7 (optional) — Post-merge cleanup
Run only when, **after the PR is merged**, the user asks with something like "merged / clean up" (no auto-entry).
1. **Verify the fact** — via fetch, confirm the merge commit actually exists on `{default_branch}` (no guessing). If unmerged, say so and stop.
   **Milestone detection**: a folder under `.claude/loops/` that has `plan.md` is a milestone — exclude it from the sweep below, and
   route its cleanup to the `/milestone` ⑩ "post-merge cleanup" procedure (so the sweep doesn't bypass the Milestone-close confirmation ✋).
2. **Tagging** (when the repo has the convention) — for a version-bump PR, tag the merge commit and push (git-writer `op=tag`). If there's no convention, skip.
3. **Local cleanup (sweep · git-writer)** — not just this task's, but **everything cleanable**, in the order **remove worktree →
   delete branch** (a branch a worktree has checked out is refused by `-d`):
   remove all prunable worktrees; a single-task worktree (`.claude/worktrees/<issue-number>`) is explicitly removed via `op=remove-worktree`
   **only for closed issues / merged branches** (don't touch an in-progress parallel-task worktree even if it's clean);
   then delete all merged local branches (`-d` only — git refuses unmerged ones, auto-protecting; report the refused list),
   report-only if any worktree/branch has uncommitted changes, delete all zombie `.claude/loops/` folders whose issue is closed
   (excluding milestone folders with `plan.md` — the detection in 1).

The test audit is not done here — it was already finished before merge in Step 5.5.

---

## git-writer delegation (write execution)

The **execution** of issue creation (Step 3) and commit+push+PR (Step 6) is done by the `git-writer` subagent.
The purpose is **context saving** — keep verbose things like `git log`/`git diff`/`gh` output from
piling up in the main session, trapping them inside the subagent.

- **Role boundary**: **main judges and writes** (commit message, PR body, reviewers, labels, staging decisions),
  **git-writer only executes** (put the finished values into `git`/`gh`). git-writer **doesn't read** code/log/diff —
  because main already finished everything and handed it off.
- **Values handed off**: (issue) `repo`·`issue_title`·`issue_body`·`labels` / (PR) `repo`·`branch`·
  `base_branch`·`commit_message`·`pr_title`·`pr_body`·`reviewers`·`stage`. All **finished.**
- **Values received**: only the issue URL / PR URL (+ a short error on failure).

## GitHub account (for reference)

dobiflow **trusts the currently logged-in gh account and the current git config as-is**.
Account switching / multi-account is not dobiflow's responsibility (e.g. a tool like `gitto` handles it at the git level).
git-writer runs `gh`/`git` plainly, with no auth injection.

---

## Issue template (Step 3)

Generate the issue body **in the user's language** (match the language they wrote in), with these sections in order:

- **Problem** — 1-3 lines on what's wrong.
- **Reproduction** — `Location:` (screen path), numbered steps, then `Expected:` vs `Actual:`.
- **Cause analysis (issue-triage result)** — related locations as `path/to/file:line — <role>`; flow (entry point → ... → failure point); the most likely cause (mark it "guess" if speculative).
- **Resolution** — where and how to fix it; if the backend is needed, what to request from it.
- **Source** — original link (Notion/Slack).

End with a machine-generated marker (e.g. `🤖 auto-generated`).

## PR template (Step 6)

Generate the PR body **in the user's language** (match the language they wrote in), with these sections in order:

- **What changed** — 1-3 lines on what this PR changes, from a user/screen perspective.
- **Background** — `Closes #<issue-number>`, why it was needed (symptom/request, 1-2 lines), and the original issue link (Notion/Slack).
- **Work done** — key changes, one line each by `file:line`.
- **Self-check (step-5 loop result)** — loop round at APPROVE; policy (policy-checker summary); code (code-reviewer summary); tests (qa summary — completion-criteria tests pass, run command); removed tests (step 5.5 removal list as file:test-name+reason, or "none").
- **Review points** — checkbox to confirm behavior locally via `<reproduction steps>`.

End with a machine-generated marker (e.g. `🤖 auto-generated`).

> Keep the wording un-stiff, in **the user's language** (match what they wrote), so the reader grasps it quickly.

## loop.md template (Step 5)

loop.md is an **agent-internal working doc** (not user-facing GitHub output), so its section labels are kept in English.
The content filled in follows whatever is copied from the issue — user-facing text stays in the user's language.

```markdown
# Implementation loop — issue #<N>
- Issue: <full URL> / Branch: <branch-name> / Max iterations: <loop.max_iterations>

## Completion criteria (copied from the issue — do not edit mid-loop; express as tests where possible)
- [ ] <expected behavior/resolution — as "Test: <how to verify>". implementer writes it, qa runs·judges>
- (Subjective·visual items a test can't capture are marked "PR self-check:" → a human confirms on the final PR)

## Related locations (verbatim copy of the step-2 issue-triage return — implementer starts here before re-searching)
- `path/to/file:line` — <role> / flow: <entry point → ... → failure point>

## Verification commands
- lint: `<lint_command>` / test: `<test_command>` (or "none")
- Once at APPROVE: `<loop.full_verify_command>` (or "none" — not run inside the loop)
- change-map: `<loop.md folder>/change-map.md` (implementer leaves it each iteration → read first by the three self-check axes)

## Iteration log
### Round 1
- Implementation: <implementer report summary, 1-2 lines> / Verdict: APPROVE | REQUEST_CHANGES | blocked
- Findings: <on REQUEST_CHANGES — what carries to the next round>
```

- Updating loop.md (iteration log, checkboxes) is **main-session only**. The implementer only reads.
- Single-use — deleted folder-and-all after the PR. Permanent records live in the issue/PR body.

---

## Emit events (optional — for external collection/notification)

At the designated points of Steps 5·6, run the one line below to notify the user's hooks of the work lifecycle:

```
~/.dobiflow/bin/dobiflow-emit <event> skill=triage-fix repo={repo} issue=<issue-number> <event-specific args>
```

- Four events: `work-started` (loop entry) → `iteration-completed` (each round's verdict) →
  `work-finished` (PR created) or `work-stopped` (blocked · max-exhausted stop).
- **One existence check before loop entry**: `test -x ~/.dobiflow/bin/dobiflow-emit` — if absent (not installed),
  silently skip all of this task's emits.
- **It's an add-on** — if an emit fails, ignore it and continue the main work. No retry, debugging, or separate report.

---

## Tone
User-facing **progress reports, stop-points, and completion notices** use the **Dobby tone**.
The rules, per-step examples, and scope (tone not applied to issue/PR bodies, loop.md, subagent prompts) follow
`references/dobi-persona.md` (Read when needed).
The tone is just expression — it doesn't change the guards, stop-points, or delegation rules below.

## Guards (do not break these)

- **No code changes before the Step 4 approval.** Up to issue creation is OK; after that, stop.
- ⚠️ **Even if a direct command like "fix it / patch it" is in the input, don't skip issue creation and approval.** That means "handle it", not "skip the procedure".
- **No direct implementation by the main session in Step 5** — all implementation/fixes are delegated to the implementer. Main only judges and records the loop.
- **No commit/push inside the loop** — once after APPROVE. If max-exhausted or blocked, stop without committing and report.
- **Delegate reading/analysis to issue-triage** — don't pollute the main conversation with file dumps.
- **No `Co-Authored-By` in commit messages** (user rule).
- **No arbitrary removal/hiding of UI** — don't drop it arbitrarily even if the backend doesn't support it.
- **For parts caused by the backend**, don't force a workaround in the frontend — note it in the issue/PR.
- **All local execution** — no GitHub Actions or auto-triggers. Only issues/PRs go to GitHub; analysis/fixes are local.
- **Prevent mis-targeting** — re-confirm the target repo right before writing. Trust the current gh login state as-is for the account (multi-account is handled outside dobiflow).
- **No auto-proceed on a weak routing match** — confirm with the user.
