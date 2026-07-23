---
name: triage-init
description: 현재 프로젝트를 분석해 triage 워크플로우 설정파일(.claude/triage.config.json)을 생성/갱신한다. 새 프로젝트에서 /triage-fix를 쓰기 전 1회 실행. 사용자가 /triage-init 으로 명시 호출할 때만.
disable-model-invocation: true
---

# triage-init — triage 설정 파일 생성

현재 프로젝트(cwd)를 분석해 `/triage-fix`·`/triage-status`가 읽을 설정을 만든다.
자동으로 감지할 수 있는 건 감지하고, **오발송 위험 있는 값(레포)만 사용자에게 확인**한다.
**멱등** — 이미 있으면 덮어쓰지 말고 diff 보여주고 갱신(사용자 입력값 보존).

> 계정은 config에 저장하지 않는다. dobiflow는 현재 로그인된 gh 계정과 현재 git 설정을
> 그대로 신뢰한다(멀티계정은 `gitto` 같은 도구가 git 레벨에서 처리).

## 출력
- `<cwd>/.claude/triage.config.json` — 프로젝트 설정 (커밋 OK)

---

## 1단계 — 자동 감지 (사용자에게 안 물음)

Bash/Read/Glob로 수집:

| 키 | 감지 방법 |
|----|----------|
| `repo` | `git remote get-url origin` → `owner/name` 정규화 (https/ssh 둘 다) |
| `default_branch` | `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (실패 시 `main`) |
| `pm` | lockfile (`pnpm-lock.yaml`→pnpm, `package-lock.json`→npm, `yarn.lock`→yarn) |
| `lint_command` | `package.json` scripts에서 `lint:fix` > `lint` > `format` 순 매칭 (`{pm} <script>`) |
| `test_command` | `package.json` scripts에서 `test:run` > `test` |
| `tech_stack` | `package.json` deps에서 식별 (react-query/zustand/react-hook-form/zod/axios/next/swr 등) |
| `policy_docs` | `.claude/docs/*.md` 글롭. 각 파일 첫 헤더 1줄을 요약으로 첨부 |
| `convention_doc` | `.claude/CLAUDE.md` 또는 `CLAUDE.md` 또는 `.claude/docs/conventions.md` 존재 확인 |
| `architecture` | `src/` 하위에 `features`/`entities`/`shared` 디렉토리 있으면 `fsd`, 아니면 추론/`flat` |
| `codeowners` | `.github/CODEOWNERS` 또는 `CODEOWNERS` 존재 시 경로, 없으면 `false` |
| `serena` | `.serena/` 존재 또는 serena MCP 등록 확인 시 `true`, 아니면 `false`. **등록 감지≠활성화** — 활성화는 각 스킬 실행 시 메인 세션이 수행(`activate_project`) |
| `bug_label` | `gh label list --repo {repo}`에 `bug` 있으면 `bug`, 없으면 첫 버그류 라벨/기본 `bug` |
| `branch_prefix` | `CLAUDE.md`에 "브랜치:" 규칙 있으면 파싱, 없으면 `{fix:"fix/", feat:"feat/", milestone:"milestone/", group:"group/"}` (마일스톤·그룹 접두사 기본 포함) |
| `commit_convention` | **그 프로젝트의 커밋 규칙.** ① `CLAUDE.md`/`CONTRIBUTING.md`의 "커밋"/"Commit" 섹션 파싱(prefix·언어·이모지 규칙). ② 없으면 `git log --oneline -30`에서 실제 패턴 추론(Conventional? gitmoji? 한글? prefix 종류?). 결과를 한 줄 규칙 + 예시 1~2개로 저장 |
| `keywords` | (선택) `CLAUDE.md` 첫 줄/README 제목에서 도메인 키워드 몇 개 추출 (라우팅 매칭용) |
| `loop` | `max_iterations`: 감지 아님 — 기본 `3` (구현 루프 최대 반복, 취향껏 수정). `full_verify_command`: `package.json` scripts에 `build` 있으면 `{pm} build` 제안, 없으면 필드 생략 — **APPROVE 시점에만 1회 도는 무거운 검증**(풀 빌드·코드 생성 등). 루프 안 반복 검증은 lint·test만이라 여기 넣은 명령은 매 반복 돌지 않는다 |
| `worktree` | 감지 아님 — 기본 `false`(취향껏 수정). `true`면 단일 작업(triage-fix·task-run)도 `<repo>/.claude/worktrees/<이슈번호>` worktree에서 구현 — 메인 워킹트리 비점유, 의존성 설치 비용 있음(설치는 `milestone.install_command` 재사용) |
| `milestone` | 마일스톤 기능값. `base_branch`: 미지정 시 `default_branch`(최종 PR 대상). `max_issues`: 기본 `10`(최대 태스크 수). `max_parallel`: 기본 `3`(병렬 그룹 폭 — worktree 비용 제한, 1이면 순차). `install_command`: `package.json` 있으면 `{pm} install` 제안(새 worktree 의존성 준비용), 불필요 스택이면 생략 |
| `models` | **진영 감지 후 provider별 기본값 생성.** 어느 진영인지: `~/.codex/` 또는 codex 실행 흔적이면 **Codex 진영**, 아니면 **Claude 진영**(기본). 매핑 원칙 = 계획·판단·검증류=상위 모델 / 커밋 등 단순 실행=하위 모델. Claude: `{planner:"opus", implementer:"opus", issue-triage:"opus", code-reviewer:"opus", policy-checker:"opus", qa:"opus", git-writer:"sonnet"}`. Codex: 같은 원칙을 그 시점 가용 gpt 계열 상·하위 등급으로(모델명은 생성 시점 확정). **에이전트 파일은 `model: inherit` 유지 — 이 config가 오버라이드(opt-in). 미지정·config 없음이면 inherit** |

## 2단계 — 사용자 확인 (AskUserQuestion)

오발송 위험·취향값만 묻는다:
- **`repo`** — 감지값이 맞는지 1회 확인(오발송 방지의 핵심).
- **`label_prefix`** — 이슈 제목 접두사. 기본 빈 값. 프로젝트 구분 표시가 필요하면 입력(예 `[gr] `).
- 1단계에서 **감지 실패/애매**한 값(정책문서 0개, CLAUDE.md 없음, lint 없음 등)만 추가 확인.

## 3단계 — 파일 쓰기

- 모든 값 → `triage.config.json` 하나로. (민감값 분리 파일 `.local.json`은 더 이상 없다 — 계정을 저장하지 않으므로.)
- **이미 존재하면**: 기존 값을 읽어 **변경점(diff)을 사용자에게 보여주고** 확인 후 갱신.
  자동 감지로 새로 잡힌 값은 추가/업데이트, **사용자가 직접 넣었던 값(label_prefix 등)은 보존**.
- 옛 `triage.config.local.json`이 남아 있으면(구버전) account·git_identity는 더 이상 안 쓴다고
  안내하고, 사용자 승인 시 정리(삭제)를 제안한다.

## 4단계 — 보고

생성/갱신된 설정을 요약 표로 보여주고, "`/triage-fix <이슈>`로 바로 쓸 수 있어요" 안내.
`serena=false`면 "이 프로젝트는 Serena LSP 미설정 — issue-triage가 grep으로 동작.
정밀 탐색 원하면 Serena 등록 권장" 한 줄 덧붙인다.
`serena=true`면 "대형 프로젝트는 `serena project index` 1회 실행 권장(콜드 스타트 단축)" 한 줄 덧붙인다.
이벤트 훅(알림·작업 수집)을 쓰려면 전역 `~/.dobiflow/hooks/on-<event>.sh` 또는 프로젝트
`.claude/dobiflow-hooks/on-<event>.sh`에 스크립트를 두면 된다고 **한 줄로만** 안내
(상세는 README "이벤트 훅" — config에 넣는 값 아님, 파일 존재만으로 동작).

## 설정 스키마 예시

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
    // 에이전트 파일은 model: inherit 유지, 이 블록이 오버라이드(opt-in). 미지정이면 inherit.
    // 계획·판단·검증류=상위 모델 / 단순 실행=하위. (아래는 Claude 진영 예 — Codex 진영은 gpt 상·하위)
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

## 가드
- **repo는 추측으로 확정 금지** — 항상 사용자 확인 1회.
- 멱등 — 덮어쓰기 전 diff 확인. 사용자 입력값 보존.
- 계정·토큰은 config에 저장하지 않는다 — dobiflow는 현재 gh 로그인·git 설정을 그대로 신뢰한다.
