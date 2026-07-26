---
name: triage-help
description: triage 워크플로우(work/triage-fix/task-run/triage-status/triage-init) 사용법을 안내한다. "어떻게 쓰지?" 싶을 때. 사용자가 /triage-help 로 호출할 때만.
---

# triage-help — usage guide

Read this skill folder's `references/triage-workflow-guide.md` and show the user a **summary of the essentials**.
If an argument is given (e.g. `/triage-help approval`), extract and explain only that topic.

## Behavior
1. Read `references/triage-workflow-guide.md` (relative to this skill folder).
2. No argument: show the "Quick start (3 steps)" + the "Commands at a glance" table + the key 1–2 lines,
   then point to "see the guide doc for details".
3. With an argument: find the matching section (config · plan · approval · event hooks, etc.) and explain that excerpt.
4. If the user is new, emphasize "`/triage-init` first, then `/work`".

## Key summary (in case you can't read the guide, at least this)
```
/triage-init   ← once per new project (creates the config)
/work <task>   ← everyday. Bug/feature classified automatically
"ok"           ← approve the issue/design and it runs all the way to the PR
/triage-status ← check current status
```
Full guide: this skill folder's `references/triage-workflow-guide.md`
