# 🧦 dobiflow

<p align="center">
  <img src="docs/assets/hero.png" alt="dobiflow — a little house-elf takes one line from task → investigate → issue → approve → fix → check → PR" width="100%">
</p>

<!-- demo.gif here: a 30s clip of Dobby filing the issue → getting approval → fixing → opening the PR -->
<!-- ![dobiflow demo — throw one line, Dobby takes it to a PR](docs/assets/demo.gif) -->

> **Just throw one line, master. Dobby does the rest. And when the PR is up… Dobby is free.**

[한국어 README](README.ko.md)

![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![Codex](https://img.shields.io/badge/Codex-CLI-000000)
![runs local](https://img.shields.io/badge/runs-100%25%20local-success)
![no API cost](https://img.shields.io/badge/extra%20API%20cost-%240-blue)
![version](https://img.shields.io/badge/version-0.11.2-lightgrey)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

Throw one bug or one task in a single line — Dobby finds the cause, files a GitHub
issue, and **once you say the word**, branches, fixes it, checks his own work, and
opens the PR. Everything runs **on your machine**. No GitHub Actions. It rides on
your Claude Code / Codex subscription, so there's **no extra API cost**.

Dobby is a good elf who only does what he's told — so he **never touches code without
permission.**

```text
> /work the dashboard logo goes nowhere when clicked

  🧦 Dobby read the issue… it's a bug. Dobby will find the cause, master.

  ✓ found the cause     Header.tsx:42 — <Logo /> has no onClick/href
  ✓ filed the issue     github.com/you/app/issues/128
  ✋ Dobby stops here    checked repo · base. May Dobby fix it, master?

> ok

  🧦 Dobby will fix it…
  🔁 implement → lint·tests → self-check (Dobby inspects himself)
     └ code-reviewer + policy-checker: no findings ✓
  ✓ everything is green   opened the PR → github.com/you/app/pull/129

  🧦 Dobby… is free!
```

## Install

### Claude Code (plugin)

```bash
# add the marketplace, then install
/plugin marketplace add NariP/dobiflow
/plugin install dobiflow@dobiflow
```

Test locally without installing:
```bash
claude --plugin-dir <clone path>
```

### Claude Code + Codex CLI (script)

After cloning, `install.sh` auto-detects which CLIs (claude/codex) are present
and installs into each home.

```bash
git clone https://github.com/NariP/dobiflow
cd dobiflow
./install.sh              # both claude & codex (whichever is detected)
# ./install.sh --claude-only / --codex-only / --link / --dry-run
```

> `--link` installs symlinks instead of copies — afterwards a plain `git pull` (or any local edit)
> takes effect immediately, no reinstall. Only use it on machines where you keep the clone around.

| Target | Install location |
|--------|------------------|
| Claude | `~/.claude/skills/*`, `~/.claude/agents/*.md` |
| Codex | `~/.agents/skills/*` + `~/.codex/skills/*` (version-compat), `~/.codex/agents/*.toml` |

> To use Serena LSP on Codex, register `[mcp_servers.serena]` in `~/.codex/config.toml`
> (optional — falls back to grep if absent).

## Quick start

```text
1.  /triage-init      ← run once per project (Dobby generates the config for you)
2.  /work <task>      ← your everyday entry. Bug or feature, Dobby routes it
3.  "ok"              ← review Dobby's issue/design, say the word → he takes it to a PR
```

Forgot how? `/triage-help` (Dobby will remind you).

## On your own vs 🧦 with Dobby

|  | On your own | 🧦 **+ dobiflow** |
|---|---|---|
| A one-line bug report | Dig through files yourself to find the cause | Dobby finds the cause, file, and line, and writes it into an issue |
| The GitHub issue | You hand-write the title and body | Dobby files it and reports the URL |
| Touching code | Straight to editing | **Never touched until you say the word** (approval gate) |
| Implementation quality | You review after it's all written | Dobby writes it, other Dobbys inspect it, and he **fixes himself** on findings |
| Domain policy | Easy to forget | policy-checker catches project-policy violations |
| Many repos | Easy to push to the wrong place | Picks the repo from the issue, re-checks it right before push |
| When stuck | Force it to a finish somehow | Dobby **stops and reports honestly** ("Dobby cannot do it, master") |
| When it's done | — | Dobby… is free 🧦 |

## Commands

| Command | Role |
|---------|------|
| `/work` | Entry point — classifies input (bug/feature) and routes to the right flow |
| `/triage-fix` | Bug — root cause → issue → fix → PR |
| `/task-run` | Feature/improvement/refactor — design → issue → build → PR (plan mode for big ones) |
| `/triage-status` | List open issues & in-progress PRs (read-only) |
| `/triage-init` | Generate per-project config (detects repo, lint, policy docs, commit rules) |
| `/triage-help` | Usage guide |

## How Dobby works

```text
/work "the dashboard logo doesn't go anywhere when clicked"
   ├─ classify     → bug → triage-fix
   ├─ investigate  → issue-triage (read-only — Dobby won't fix on a whim)
   ├─ GitHub issue → git-writer Dobby files it (execution only) + URL reported
   ├─ ✋ approval   → confirm repo · base, then "may Dobby fix it, master?"
   ├─ loop 🔁      → implementer Dobby codes + lint/tests
   │                 → policy-checker + code-reviewer (Dobbys inspect in parallel)
   │                 → ❌ findings? Dobby fixes himself (max 3, configurable)
   └─ PR           → main writes the message/body, git-writer Dobby runs commit+push+PR → URL
                     → 🧦 Dobby is free!
```

More detail: [`docs/triage-workflow-guide.md`](docs/triage-workflow-guide.md).
Why it's built this way (phase-by-phase pattern map): [`docs/architecture.md`](docs/architecture.md).

## Dobby's promises (requirements & limits — read this)

dobiflow runs everything **on your machine**, so Dobby keeps a few rules:

- **The target repo must be cloned locally.** Routing picks the repo from your
  cloned repos. If the repo isn't on your machine, Dobby stops and asks you to clone
  it first — he never clones a repo on his own.
- **It's for code work (bugs / features / refactors).** Classification reads the
  *whole request*, not just the title — if there's any implementation work (a popup,
  a button, link wiring, a "don't show again" toggle…), it's a feature even if the
  title says "terms" or "policy". Only requests with **no code work at all** (pure
  legal copy, docs, ops) are out of scope; mixed requests are split (code part runs,
  non-code part is flagged).
- **When unsure, Dobby asks.** If it's unsure which repo, it asks instead of guessing.
- **Writes are gated.** Before creating an issue/PR Dobby re-checks the target repo
  (to avoid pushing to the wrong place), and you approve before any code is touched.
  Dobby uses whatever GitHub account you're currently logged into — account switching
  is out of scope (a tool like `gitto` handles that at the git level).

## What Dobby is good at

- **Claude Code + Codex** — same workflow on both CLIs (skills, subagents, plan mode map natively)
- **Any input** — Notion link / Slack link / plain text
- **Approval gate** — the issue gets created, but no code is touched until you say "ok"
- **Multi-repo** — infers the right repo from the issue (asks when unsure)
- **Project rules first** — commit convention, policies, conventions follow the target project
- **Implementation loop** — an implementer Dobby codes while reviewer Dobbys judge; findings trigger automatic re-implementation until green (bounded — stops and reports instead of forcing a PR)
- **Split self-check** — domain-policy check and general code review run separately (read-only Dobbys)
- **Context-thrifty writes** — a `git-writer` Dobby runs issue/commit/push/PR as pure execution; main writes the message/body, git-writer just runs `gh`/`git` and returns the URL, so verbose `git log`/`diff`/`gh` output never piles up in the main session
- **Code search** — symbol-level via Serena LSP when available, grep fallback otherwise

## Event hooks (optional)

Dobby fires hooks at key moments while he works, so you can run **your own
script** — Slack/Telegram notification, logging, collecting in-progress tasks
across sessions and repos into an external service, anything.

| Event | When | Key env vars (always: `DOBIFLOW_EVENT`, `DOBIFLOW_CWD`) |
|---|---|---|
| `issue-created` | GitHub issue created | `DOBIFLOW_URL`, `DOBIFLOW_COMMAND` |
| `pr-created` | GitHub PR created | `DOBIFLOW_URL`, `DOBIFLOW_COMMAND` |
| `work-started` | implementation loop entered (Dobby clocks in) | `DOBIFLOW_{SKILL,REPO,ISSUE,ISSUE_URL,BRANCH,TITLE}` |
| `iteration-completed` | after each loop verdict | `DOBIFLOW_{SKILL,REPO,ISSUE,ITERATION,VERDICT}` |
| `work-finished` | PR shipped (🧦 Dobby is free!) | `DOBIFLOW_{SKILL,REPO,ISSUE,PR_URL,ITERATIONS}` |
| `work-stopped` | loop aborted (blocked / max iterations) | `DOBIFLOW_{SKILL,REPO,ISSUE,REASON}` |

Drop an executable script at either location (or both):

```text
~/.dobiflow/hooks/on-<event>.sh                    # global (all projects)
<repo>/.claude/dobiflow-hooks/on-<event>.sh        # per-project
```

- `issue-created`/`pr-created` — auto-detected by a Claude Code PostToolUse hook
  watching `gh` commands (requires `jq`).
- `work-*`/`iteration-*` — work-lifecycle events, emitted by the skills via
  `~/.dobiflow/bin/dobiflow-emit` (installed by install.sh — silently skipped
  when absent; works for both Claude and Codex).
- See `hooks/examples/` for templates. Hook failures never block Dobby's main work.

## Dependencies (recommended)

- **GitHub CLI (`gh`)** — creates issues/PRs. Requires auth (`gh auth login`).
- **Serena MCP** (optional) — symbol-level code search. Falls back to grep if absent.
  Register at user scope: `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code`

## License

MIT

<sub>🧦 The "Dobby" in dobiflow is this project's mascot — a little house-elf who works on permission and is free when the job is done. Not affiliated with any particular work of fiction.</sub>
