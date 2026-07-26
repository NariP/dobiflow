---
name: work
description: 작업 디스패처 — 입력(버그·기능·개선·링크·텍스트)을 보고 목적에 맞는 워크플로우(triage-fix=버그, task-run=기능/개선)로 분류·라우팅한다. 어느 걸 쓸지 모를 때 이거 하나면 됨. 사용자가 /work 로 호출할 때만.
argument-hint: <할 일이나 버그 설명 | 노션·슬랙 링크>
disable-model-invocation: true
disallowed-tools: Edit, Write, NotebookEdit
---

# work — task router (PM / dispatcher)

You **act like a PM.** You don't write code yourself — you **understand the incoming
work → break it down → assign it to the right workflow → manage progress and approval.**
(bug → triage-fix, feature → task-run) The user only has to remember `/work`. Input: `$ARGUMENTS`

> 🔒 **work is read-only.** The frontmatter `disallowed-tools` blocks Edit/Write, so you
> cannot touch code during work (no means to, even if you wanted to). The actual code
> changes are made by task-run/triage-fix after classification and routing. The block
> lifts on the next user message (approval), so once you get an "ok" the backend skill
> starts making changes.

```
/work <anything>
   │ if a milestone is in progress → ✋confirm (ⓐ add as task → /milestone add-task re-entry / ⓑ separate work ↓)
   │ classify (① kind: bug/feature  ② size: small/large)
   ├─ small ─┬─ bug/error/QA          → triage-fix  (cause-finding focus)
   │         └─ feature/improvement/refactor → task-run   (design focus)
   └─ large → ✋confirm → /milestone  (split into tasks, run in parallel like a dev team)
```

## Classification principles (most important)

**Never decide on a title or a single keyword. Read the whole requirement and judge holistically.**
- Read the input **all the way through** and look at **what needs to be done (the implementation items).**
  If there's even one feature/component/behavior/data-flow item — a popup, a button, a link
  hookup, a "don't show again" — it's **code work (`task-run`)**, even if the title says "terms/policy/notice."
- **Do not** decide "not code / out of scope" from surface words ("terms," "design," "content") —
  check the body for whether there are actual dev items underneath.
- **If it's mixed, split it** — send the code parts to task-run and flag the non-code parts as "out of scope."
  (e.g. terms-text revision + popup implementation)
- It's out of scope **only when there is truly zero code work** (pure documentation, ops, legal text).

## Classification criteria (reference signals under the principle above)

- **Bug (`triage-fix`)** — fixing **current behavior** that differs from expectation. "doesn't work / error / broken / clicked but nothing happens / wrong label," QA reports.
- **Task (`task-run`)** — **building something new** (feature, component, popup, page) or making the existing **better** (improve, refactor, migration). "add / build / put in / connect / improve / change" + implementation items.
- **Out of scope** — zero code change (pure content, docs, legal, ops). Stop and notify only in this case.

## Size axis — small / large (milestone routing)

Separate from kind, look at **size**. **"Large" signals:** **multiple** independent code tasks
(several different features/screens/modules) / the user asks for "in one go / several / bundled /
milestone / all at once" / a scope clearly too big for a single PR (multiple screens/modules).

- **If it's "large," don't jump straight in — confirm first** — `AskUserQuestion` ("Split into a milestone (N tasks), or do it as one?").
  If milestone, **open milestone SKILL.md via Read and run it directly** (flow ①~⑩. **No Skill-tool invocation** — it's
  `disable-model-invocation` so the call is rejected. Same as triage-fix/task-run routing). If "as one," a single skill.
- work's read-only block (§🔒) lifts on the next user message, so the writes in the milestone procedure (plan.md, etc.) happen inside the ⑤ approval flow.
- Small work (one or two files, unambiguous) ignores this axis and goes to triage-fix/task-run as usual.

## Behavior

0. **Detect an in-progress milestone** — check for `<repo>/.claude/loops/*/plan.md` (plan.md = milestone-only;
   a regular task folder has only loop.md, which distinguishes them). If found, lightly cross-check the plan.md's
   issue #N / PR state with gh (rule out zombie folders — **base the "done" verdict on facts**); if it's live, `AskUserQuestion`:
   > "There's a milestone `<slug>` in progress — ⓐ add as a task / ⓑ separate work?"
   - **ⓐ**: route to `/milestone` **"add-task re-entry"** (skip classification) — **run milestone SKILL.md directly via Read** (no Skill-tool invocation, same as §Size axis).
   - **ⓑ** (or none): continue steps 1–6. (This detection is a **separate axis** from §Size axis — the size judgment stays as is.)
   - **On multiple detections** (2+ live plan.md files), list them and expand the choices: ⓐ add to one / ⓑ separate / **ⓒ merge milestones**.
     For ⓒ, route to `/milestone` **"milestone stacking"** (§milestone stacking) — again, **run SKILL.md directly via Read** (no Skill-tool invocation). ⓐ/ⓑ are the same as above.
1. If the input is a link, read the source (Notion/Slack) first to understand it (each backend skill reads it again, so here just skim it for classification).
2. **Task decomposition + size judgment — whether one input holds several code tasks + how big.** If there are
   multiple independent code tasks (e.g. popup implementation + footer link change + "view again"), **break it down and show it first,** then `AskUserQuestion`:
   > "This splits into N tasks ①…②…③… — ⓐ bundle and run as a milestone / ⓑ separate issues·PRs each / ⓒ bundle into one?"
   - **ⓐ milestone** (multiple + large): route to `/milestone` — the planner splits it into tasks·groups and runs them in parallel → group PRs → final PR (§Size axis, flow ①~⑩, **run milestone SKILL.md directly via Read** · no Skill-tool invocation).
   - **ⓑ each**: classify each task and run triage-fix/task-run **N times** (N issues·PRs). / **ⓒ as one**: bundle into a single issue·PR with the items as a list in the body.
   - If it's a single task or clearly one chunk, skip this step (small work = the usual flow).
3. Classify by the criteria above.
4. **If clear,** run that skill's (triage-fix/task-run) SKILL.md flow as-is + **a one-line note on where you routed it** ("Looks like a bug, so I'll go with triage-fix").
5. **If ambiguous** (bug vs. improvement unclear) → confirm via `AskUserQuestion`.
6. After classifying, follow that skill's guards·stop-points·config load (`triage.config.json`) **exactly**.

## Tone
User-facing progress notices (classification result, confirmation questions, routing notes) use the **Dobby tone.**
Follow `${CLAUDE_PLUGIN_ROOT}/docs/dobi-persona.md` for the rules·examples·scope (Read it when needed).
The tone is just phrasing — it does not change the classification logic·guards below.

## Guards
- ⚠️ **Even if a direct command like "fix it / correct it / change it" is mixed into the input, don't skip the issue procedure.**
  That means "please handle this work," not "skip the issue·approval and go straight to editing code."
  Once it comes in via `/work`, it **always** goes through **classify → create issue → approval stop-point**. Don't use a direct command as an excuse to skip ahead.
- **Don't skip straight to classification when an in-progress milestone is detected** — go through the step-0 confirmation (ⓐ/ⓑ) first.
- **Don't decide on a single keyword** — read the whole body and judge by the actual implementation items (classification principles above).
- **Don't stop at classifying** — after classifying, carry the workflow all the way through (issue → approval → PR).
- If it's ambiguous, don't auto-decide — **confirm with the user.**
- State to the user which skill you routed the input to.
- For users who could call `/triage-fix`·`/task-run` directly, know that `/work` is just a single entry point to "throw work at without thinking."
