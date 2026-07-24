# Triage Workflow Guide

> A global toolkit that takes an issue/task and automatically runs it locally, all the way from
> **understand → GitHub issue → approval → implementation loop (implement → verify → self-check) → PR**.
> Works in any project.

---

## 🚀 Quick start (3 steps)

```
1.  /triage-init      ← just once per new project (auto-generates the config)
2.  /work <task>      ← everyday, just this. Throw a bug or feature at it and it classifies automatically
3.  "ok"              ← review the created issue/design, approve → runs all the way to the PR
```

For a project you're using for the first time, **`/triage-init` first**. After that, just remember `/work`.

---

## 📋 Commands at a glance

| Command | When | What |
|------|------|--------|
| **`/work`** | When you know what to do (most of the time) | Reads the input, classifies bug/feature · size → routes to the right workflow |
| `/triage-fix` | When it's clearly a bug | Find cause → issue → fix → PR |
| `/task-run` | Feature add · improvement · refactor | Design → issue → implement → PR |
| `/milestone` | Big work (large enough to split into multiple tasks) | Task split · grouping → parallel group execution → group PR → final PR |
| `/triage-status` | When you want to see what's currently open | List of open issues · in-progress PRs (read-only) |
| `/triage-init` | New project first time / config refresh | Creates `.claude/triage.config.json` |

> 💡 **`/work` alone is enough.** You can call `/triage-fix` · `/task-run` directly, but
> if you're unsure, just throw it at `/work` and it routes for you.

---

## 🔤 Any input is OK

It takes all three:
- **Notion link** — a QA page URL → reads the content automatically
- **Slack link** — a message/thread URL → reads it automatically
- **Plain text** — describe it in words, like "clicked the logo on the dashboard and nothing happened"

Examples:
```
/work https://notion.so/...QA page...
/work add sorting to the candidate-site comparison table
/triage-fix login shows a blank white screen
```

---

## 🔄 Full flow (bug example)

```
/work clicked the dashboard logo and nothing happened
   │
   ├─ 0. Milestone detect → if a milestone is in progress ✋ "Add as a task?" (ⓐ → re-enter the milestone)
   ├─ 1. Classify      → "Looks like a bug, proceeding with triage-fix"
   ├─ 2. Find cause    → issue-triage traces the code (Serena LSP / grep)
   ├─ 3. GitHub issue  → create + report the full URL
   ├─ 4. ✋ Approval     → "Created issue #N: <URL> / confirm repo · base / shall I fix it?"
   │                       ← you say "ok"
   ├─ 5. Impl loop 🔁  → the implementer agent implements + lint · test
   │                    → policy (policy-checker) + code quality (code-reviewer) checks in parallel
   │                    → ❌ if issues are raised, auto re-implement (up to 3 times, configurable)
   └─ 6. PR           → after checks pass: commit + create + assign reviewer + report the full URL
```

**For features (task-run) steps 2 · 4 differ:** instead of "find cause" it's **"design"**, and approval is
"shall I build it this way?" (agreeing on direction). For big work, **plan mode** is recommended.

---

## 🏗️ Big work becomes a milestone (split and run like a dev team)

When `/work` judges the scope to be **big** (several independent code tasks · multiple screens · modules), it confirms and
routes to `/milestone`. It splits the big work into small tasks, bundles related ones into **groups**
(a group = one developer), and runs **groups in parallel · tasks within a group sequentially**.

```
/milestone <big work>
   │
   ├─ ① Understand · split → planner splits into tasks with file plans · completion criteria (tests) · grouping
   ├─ ⑤ ✋ Approval        → confirm the plan + execution mode [stop / bypass] in one go
   ├─ ⑥⑦ Issues · branches → Milestone · issues · milestone branch · group branches · worktree (git-writer)
   ├─ ⑧ Group execution 🔁 → each task reuses the formal implementation loop, committing to the group branch
   ├─ ⑨ Group PR          → must pass pre-merge verification (qa full_verify, merge-queue style) to merge into the milestone
   └─ ⑩ ✋ Final PR        → milestone → main PR; merging into main is always done by a human
```

**Three branch layers** `main → milestone/<slug> → group/<slug>-<group>` (no per-task branches).
**If it gets stuck or integration breaks**, it doesn't force through — it **leaves a new issue** and continues; only successful tasks get committed.
**If a new fix comes in mid-flight**, `/work` detects the milestone and can **add it as a task** —
after re-plan approval ✋ it creates an issue, runs it in the relevant group, and joins the group PR → final PR flow.

**You can also stack another milestone on top of one in progress (stacking)** — while A waits for its main merge, a follow-up
milestone C starts based on A's branch (the base choice is confirmed together at the approval stop point). Numbers ①~⑥ correspond
to the "milestone stacking" procedure in `/milestone`.

```
main ────────────────▶ ⑤ Converge: A→main first, then C→main
 ├─ A (milestone in progress, awaiting merge)
 │   └─ C (follow-up milestone, ① base=A) ◀── ② cherry-pick B's tasks worth keeping + full_verify
 │        · ③ C's final PR base is A (not main) — auto-retargets when A merges · branch is deleted
 │        · ④ as A advances, periodically merge-in to C (avoids staleness)
 │        · ⑤ merge C only after A's remote branch is deleted — retarget only fires on base deletion (merge earlier and it goes into A)
 └─ B (absorbed) ──▶ ⑥ Milestone close · issue transfer · branch cleanup
```

---

## ✋ Approval stop points (peace-of-mind points)

- **The issue does get created**, but after that **the code is only touched once you say "ok"**.
- Nothing is modified before approval. If the direction is wrong, just say so and correct it then.
- When reporting an issue/PR, it also shows the **repo · base branch** (prevents landing in the wrong place).

---

## ⚙️ Config (`/triage-init` auto-generates it)

Each project's own values go into `.claude/triage.config.json`:
- Repo name, default branch, lint command, test command
- Policy doc list, convention doc, tech stack, architecture
- **Commit rules** (that project's style takes priority — Conventional, gitmoji, or Korean)
- Label/branch prefixes, whether CODEOWNERS exists, whether Serena is used

`/triage-init` **auto-detects** everything + asks just once about risky values like the repo.
(It does not store accounts — it trusts the current gh login · git config as-is. Multi-account is handled by `gitto` etc.)
If things change later, run `/triage-init` again to refresh (existing config is preserved).

---

## 🧩 Features

- **Everything runs locally** — no GitHub Actions. Only issues/PRs go to GitHub; understanding · fixing happens on your machine.
  (Runs on your Claude Code subscription, zero extra API cost)
- **Multi-repo** — reads the issue content and picks the right repo automatically (asks if ambiguous).
- **Code search** — uses Serena LSP (symbol-level precision) if available, falls back to grep otherwise.
- **Implementation loop** — implementation (implementer) and checks (policy-checker + code-reviewer) are handled by different agents,
  and ❌ if issues are raised it auto re-implements. It loops until green, and if it exceeds the max count (default 3) it
  stops and reports — it never forces a PR up.
- **Iteration is cheap** — from the 2nd round on, it's not a full re-check but **the previous issues + only what changed this round**.
  Heavy verification like a full build isn't repeated inside the loop but done once at APPROVE time
  (`loop.full_verify_command`, when set).
- **Self-check separation** — domain policy checks (policy-checker) and general code review (code-reviewer) are kept separate.
- **Debt-test audit** — before commit · PR (for milestones, in one batch before the final PR), it audits **only the tests this work added**
  on the "if it breaks, is it a bug or a refactor?" criterion, stripping out implementation-detail-coupled, self-evident, and duplicate tests.
  It doesn't touch existing tests, and re-confirms the remaining tests are green after removal — no debt lands on main.
- **Post-merge cleanup (optional)** — after a PR is merged, say "merged / clean it up" and it confirms the merge → (if the repo's convention) tags →
  batch-cleans merged local branches · prunable worktrees · zombie loops folders (unmerged is auto-protected).
- **Single-task worktree (optional)** — with config `worktree: true`, even a single bug/feature task is implemented in a
  `.claude/worktrees/<issue-number>` worktree, so it doesn't occupy the main working tree while you work
  (default false — has a dependency-install cost; falls back to the current method if creation fails).
- **Event hooks (optional)** — on issue/PR creation (`issue-created` · `pr-created`) and on the implementation loop's
  start · iteration · end (`work-started` · `iteration-completed` · `work-finished` · `work-stopped`), it runs
  **scripts you define**. Use it for notifications · logs · externally collecting work running across multiple sessions
  (see README "Event hooks").

---

## ❓ FAQ

**Q. What's the difference between `/work` and `/triage-fix`?**
`/work` is the entry point (classifier). If a milestone is in progress, it detects it before classifying and first asks
whether to add a task; then for a bug it routes to `/triage-fix`, for a feature to `/task-run`, automatically.
If you know where it should go, call it directly; if not, use `/work`.

**Q. I ran `/work` on a new project and it acted weird.**
You probably didn't run `/triage-init`. Let's create the config with `/triage-init` first.
(It works with defaults even without config, but the repo · account · commit rules may not match.)

**Q. Where do I see the created issue/PR?**
When it reports, it gives a **clickable full URL**. To see the status again, use `/triage-status`.

**Q. It's a big feature and I want to design first.**
If `/task-run` (or `/work`) judges the scope to be big, it recommends **plan mode**.
In plan mode it writes a plan first, then implements after your approval.

**Q. What if the implementation loop runs the max count (3) and still isn't done?**
It stops without commit · PR and reports the situation (the work branch is kept). Whether to continue, change direction,
or look yourself is up to you. Adjust the max count with `loop.max_iterations` in `triage.config.json`.

**Q. What's the commit message format?**
It follows that project's rules (`/triage-init` detects them). Co-Authored-By is never added.

**Q. How do I resume work already in progress?**
For the conversation session, use Claude Code's built-in `claude --resume` / `--continue`.
For work stacked on GitHub, check the list with `/triage-status` and check out the relevant branch.

**Q. I want to gather work running across multiple sessions · repos in one place.**
For a per-repo snapshot, use `/triage-status`. To collect in real time across sessions, use **event hooks** —
at each loop start/end, your script like `~/.dobiflow/hooks/on-work-started.sh` is called,
so send it to an external service from there (see README "Event hooks", `hooks/examples/` templates).

---

## 📂 Layout (for reference)

Inside the `dobiflow` plugin:
```
skills/   work · milestone · triage-fix · task-run · triage-status · triage-init · triage-help
agents/   issue-triage · planner (planning) · qa (test run · verdict) · policy-checker · code-reviewer (read-only) · implementer (implementation) · git-writer (write execution)
hooks/    hooks.json (registers PostToolUse) · examples/ (user hook templates)
scripts/  dobiflow-hook.sh (auto-detects issues/PRs) · dobiflow-emit.sh (publishes work lifecycle)
docs/     triage-workflow-guide.md  (this guide)
```

Each project only gets a config created (made by `/triage-init`):
```
<project>/.claude/
  ├── triage.config.json       # project config
  ├── loops/<issue-number>/loop.md  # implementation loop work file (single-use — deleted after PR, not git-tracked)
  └── dobiflow-hooks/on-<event>.sh # (optional · write it yourself) per-project event hook
```
