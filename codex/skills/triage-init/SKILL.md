---
name: triage-init
description: 현재 프로젝트를 분석해 triage 워크플로우 설정파일(.claude/triage.config.json)을 생성/갱신한다. 새 프로젝트에서 /triage-fix를 쓰기 전 1회 실행. 사용자가 /triage-init 으로 명시 호출할 때만.
---

# triage-init — Generate the triage config file

Analyzes the current project (cwd) to build the config that `/triage-fix` and `/triage-status` will read.
Auto-detect whatever can be detected, and **only confirm values with a mis-send risk (the repo) with the user**.
**Idempotent** — if it already exists, don't overwrite; show a diff and update (preserving user-entered values).

> Accounts are never stored in the config. dobiflow trusts the currently logged-in gh account and the current git
> settings as-is (multi-account is handled at the git level by tools like `gitto`).

## Output
- `<cwd>/.claude/triage.config.json` — project config (safe to commit)

---

## Step 1 — Auto-detection (nothing asked of the user)

Collect via Bash/Read/Glob:

| Key | Detection method |
|-----|------------------|
| `repo` | `git remote get-url origin` → normalize to `owner/name` (both https/ssh) |
| `default_branch` | `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (falls back to `main`) |
| `pm` | lockfile (`pnpm-lock.yaml`→pnpm, `package-lock.json`→npm, `yarn.lock`→yarn) |
| `lint_command` | match `package.json` scripts in the order `lint:fix` > `lint` > `format` (`{pm} <script>`) |
| `test_command` | match `package.json` scripts: `test:run` > `test` |
| `tech_stack` | identify from `package.json` deps (react-query/zustand/react-hook-form/zod/axios/next/swr, etc.) |
| `policy_docs` | glob `.claude/docs/*.md`. Attach each file's first header line as a summary |
| `convention_doc` | check for `.claude/CLAUDE.md`, `CLAUDE.md`, or `.claude/docs/conventions.md` |
| `architecture` | if `features`/`entities`/`shared` directories exist under `src/`, `fsd`; otherwise infer/`flat` |
| `codeowners` | if `.github/CODEOWNERS` or `CODEOWNERS` exists, its path; otherwise `false` |
| `serena` | `true` if `.serena/` exists or a serena MCP registration is detected; otherwise `false`. **Registration detected ≠ activated** — activation is done by the main session at each skill run (`activate_project`) |
| `bug_label` | if `bug` exists in `gh label list --repo {repo}`, `bug`; otherwise the first bug-type label / default `bug` |
| `branch_prefix` | if `CLAUDE.md` has a "branch:" rule, parse it; otherwise `{fix:"fix/", feat:"feat/", milestone:"milestone/", group:"group/"}` (milestone/group prefixes included by default) |
| `commit_convention` | **The project's commit rules.** ① Parse the "commit"/"Commit" section of `CLAUDE.md`/`CONTRIBUTING.md` (prefix/language/emoji rules). ② If absent, infer the actual pattern from `git log --oneline -30` (Conventional? gitmoji? Korean? what prefix kinds?). Store the result as a one-line rule + 1–2 examples |
| `keywords` | (optional) extract a few domain keywords from `CLAUDE.md`'s first line / README title (for routing matches) |
| `loop` | `max_iterations`: not detected — default `3` (max iterations of the implementation loop, tune to taste). `full_verify_command`: if `package.json` scripts has `build`, suggest `{pm} build`; otherwise omit the field — **the heavy verification that runs once only at APPROVE time** (full build, code generation, etc.). Iterative in-loop verification is lint/test only, so the command placed here does not run on every iteration |
| `worktree` | not detected — default `false` (tune to taste). If `true`, even single tasks (triage-fix/task-run) are implemented in a `<repo>/.claude/worktrees/<issue-number>` worktree — the main working tree stays free, at the cost of installing dependencies (installation reuses `milestone.install_command`) |
| `milestone` | Milestone feature values. `base_branch`: if unset, `default_branch` (the final PR target). `max_issues`: default `10` (max number of tasks). `max_parallel`: default `3` (parallel group width — caps worktree cost; `1` means sequential). `install_command`: if `package.json` exists, suggest `{pm} install` (to prepare a new worktree's dependencies); omit for stacks that don't need it |
| `models` | **Detect the camp, then generate provider-specific defaults.** Which camp: if `~/.codex/` or traces of a codex run exist, **Codex camp**; otherwise **Claude camp** (default). **Mapping principle = planning/judgment/verification roles (planner/implementer/issue-triage/code-reviewer/policy-checker/qa) = higher-tier model / judgment-free "hands" agent (git-writer — runs gh/git with the finished values it's given) = lower-tier model.** This split is the multi-agent standard of orchestrator=strong model, worker=cheap. **⚠️ qa is not a downshift target** — as the arbiter that audits completion-criteria tests and rules pass/fail, it keeps the strong model (config.models.qa applies globally to self-checks too). Claude: `{planner:"opus", implementer:"opus", issue-triage:"opus", code-reviewer:"opus", policy-checker:"opus", qa:"opus", git-writer:"sonnet"}`. Codex: apply the same principle with the higher/lower tiers of the gpt line available at that time (model names finalized at generation time). **Dropping git-writer further, down to a Haiku tier, is only allowed after passing a per-op scenario evaluation (command ordering and adherence to prohibitions across missing stage / merge SHA mismatch / conflict / dirty worktree / same-name milestone / remote-delete failure)** — git-writer also has no open judgment, but it's not low-risk (reusing the same Milestone, merging the verified SHA as-is, deleting remote branches), so the default is sonnet. **Agent files carry no model field and keep session-model inheritance — this config overrides it (opt-in). If unspecified or no config, inherit the session model** |

## Step 2 — User confirmation (AskUserQuestion)

Only ask about mis-send risks and taste values:
- **`repo`** — confirm once whether the detected value is correct (the core of mis-send prevention).
- **`label_prefix`** — issue-title prefix. Empty by default. Enter one if you need a project-distinguishing marker (e.g. `[gr] `).
- Only additionally confirm values that **failed/were ambiguous** in Step 1 (0 policy docs, no CLAUDE.md, no lint, etc.).

## Step 3 — Write the file

- All values → into a single `triage.config.json`. (There is no longer a separate sensitive-value file `.local.json` — since accounts aren't stored.)
- **If it already exists**: read the existing values, **show the user the changes (diff)**, and update after confirmation.
  Add/update newly auto-detected values, but **preserve values the user entered directly (label_prefix, etc.)**.
- If an old `triage.config.local.json` remains (legacy), inform the user that account/git_identity are no longer used,
  and, upon user approval, offer to clean it up (delete it).

## Step 4 — Report

Show the created/updated config as a summary table and note "you can use `/triage-fix <issue>` right away."
If `serena=false`, add one line: "This project has no Serena LSP configured — issue-triage runs on grep.
For precise navigation, registering Serena is recommended."
If `serena=true`, add one line: "For large projects, running `serena project index` once is recommended (shortens cold start)."
To use event hooks (notifications, task collection), note in **one line only** that placing a script at the global
`~/.dobiflow/hooks/on-<event>.sh` or the project `.claude/dobiflow-hooks/on-<event>.sh` enables them
(details in the README "Event hooks" — not a config value; it works by the file's mere existence).

## Config schema example

```jsonc
// triage.config.json
{
  "repo": "owner/name",
  "default_branch": "main",
  "pm": "pnpm",
  "lint_command": "pnpm biome check --write .",
  "test_command": "pnpm test:run",
  "tech_stack": { "server_state": "react-query", "client_state": "zustand", "form": "react-hook-form+zod", "http": "axios" },
  "policy_docs": [".claude/docs/layout-policy.md", "..."],
  "convention_doc": ".claude/CLAUDE.md",
  "architecture": "fsd",
  "codeowners": ".github/CODEOWNERS",
  "serena": true,
  "bug_label": "bug",
  "branch_prefix": { "fix": "fix/", "feat": "feat/", "milestone": "milestone/", "group": "group/" },
  "loop": { "max_iterations": 3, "full_verify_command": "pnpm build" },
  "worktree": false,
  "milestone": { "base_branch": "main", "max_issues": 10, "max_parallel": 3, "install_command": "pnpm install" },
  "models": {
    // Agents keep session-model inheritance; this block overrides it (opt-in). If unspecified, inherit.
    // planning/judgment/verification roles = higher-tier model / judgment-free "hands" (git-writer) = lower. (Codex camp uses gpt higher/lower)
    // qa is an arbiter, so no downshift (keep the strong model). Dropping git-writer further to Haiku only after passing the per-op scenario evaluation.
    "planner": "opus", "implementer": "opus", "issue-triage": "opus",
    "code-reviewer": "opus", "policy-checker": "opus", "qa": "opus", "git-writer": "sonnet"
  },
  "commit_convention": {
    "rule": "Conventional Commits (feat/fix/chore/refactor/docs/test). 제목 한국어/영어 혼용 OK. Co-Authored-By 금지.",
    "examples": ["fix(hub): 대시보드 로고 이동 수정", "feat(gr-map): 후보지 검색 필터 추가"]
  },
  "label_prefix": "",
  "keywords": ["검색", "지도", "결제"]
}
```

## Guards
- **Never finalize repo by guesswork** — always confirm with the user once.
- Idempotent — verify the diff before overwriting. Preserve user-entered values.
- Accounts/tokens are never stored in the config — dobiflow trusts the current gh login and git settings as-is.
