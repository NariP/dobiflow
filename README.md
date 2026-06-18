# triage-flow

> 한국어: [README.ko.md](README.ko.md)

A Claude Code / Codex plugin that takes an issue or task and runs it **locally**
all the way through: **understand → GitHub issue → approval → fix → self-check → PR**.

Throw a bug or a feature in one line. It classifies the input, investigates the
root cause (or designs the change), opens a GitHub issue, and — once you approve —
branches, fixes, and opens a PR. Everything runs **locally** (no GitHub Actions),
on your Claude Code / Codex subscription, so there's no extra API cost.

## Install

### Claude Code (plugin)

```bash
# add the marketplace, then install
/plugin marketplace add NariP/triage-flow
/plugin install triage-flow@triage-flow
```

Test locally without installing:
```bash
claude --plugin-dir <clone path>
```

### Claude Code + Codex CLI (script)

After cloning, `install.sh` auto-detects which CLIs (claude/codex) are present
and installs into each home.

```bash
git clone https://github.com/NariP/triage-flow
cd triage-flow
./install.sh              # both claude & codex (whichever is detected)
# ./install.sh --claude-only / --codex-only / --dry-run
```

| Target | Install location |
|--------|------------------|
| Claude | `~/.claude/skills/*`, `~/.claude/agents/*.md` |
| Codex | `~/.agents/skills/*` + `~/.codex/skills/*` (version-compat), `~/.codex/agents/*.toml` |

> To use Serena LSP on Codex, register `[mcp_servers.serena]` in `~/.codex/config.toml`
> (optional — falls back to grep if absent).

## Quick start

```
1.  /triage-init      ← run once per project (auto-generates config)
2.  /work <task>      ← your everyday entry. Bug or feature, it routes for you
3.  "ok"              ← review the issue/design, approve → it goes to PR
```

Forgot how? `/triage-help`.

## Commands

| Command | Role |
|---------|------|
| `/work` | Entry point — classifies input (bug/feature) and routes to the right flow |
| `/triage-fix` | Bug — root cause → issue → fix → PR |
| `/task-fix` | Feature/improvement/refactor — design → issue → build → PR (plan mode for big ones) |
| `/triage-status` | List open issues & in-progress PRs (read-only) |
| `/triage-init` | Generate per-project config (detects repo, lint, policy docs, commit rules, account) |
| `/triage-help` | Usage guide |

## How it works

```
/work "the dashboard logo doesn't go anywhere when clicked"
   ├─ classify     → bug → triage-fix
   ├─ investigate  → issue-triage (read-only)
   ├─ GitHub issue → created + URL reported
   ├─ ✋ approval   → confirm repo · account, then "fix it?"
   ├─ fix          → branch + minimal change + lint
   ├─ self-check   → policy-checker + code-reviewer (parallel)
   └─ PR           → created + reviewer + URL
```

More detail: [`docs/triage-workflow-guide.md`](docs/triage-workflow-guide.md).

## Requirements & limits (read this)

triage-flow runs everything **on your machine**, so a few conditions must hold:

- **The target repo must be cloned locally.** Routing picks the repo from your
  cloned repos. If the repo isn't on your machine, it stops and asks you to clone
  it first — it never clones a repo on its own.
- **It's for code work (bugs / features / refactors).** Things like editing legal
  copy, terms-of-service text, or pure content/ops tasks are out of scope — `/work`
  will say so and stop instead of forcing an issue.
- **Weak routing matches aren't auto-run.** If it's unsure which repo, it asks.
- **Writes are gated.** Before creating an issue/PR it re-checks the active GitHub
  account (to avoid pushing to the wrong account), and you approve before any code
  is touched.

## Features

- **Claude Code + Codex** — same workflow on both CLIs (skills, subagents, plan mode map natively)
- **Any input** — Notion link / Slack link / plain text
- **Approval gate** — the issue gets created, but no code is touched until you say "ok"
- **Multi-repo** — infers the right repo from the issue (asks when unsure)
- **Multi-account** — different GitHub account per repo; re-checks account right before writing
- **Project rules first** — commit convention, policies, conventions follow the target project
- **Split self-check** — domain-policy check and general code review run separately (read-only agents)
- **Code search** — symbol-level via Serena LSP when available, grep fallback otherwise

## Dependencies (recommended)

- **GitHub CLI (`gh`)** — creates issues/PRs. Requires auth (`gh auth login`).
- **Serena MCP** (optional) — symbol-level code search. Falls back to grep if absent.
  Register at user scope: `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code`

## License

MIT
