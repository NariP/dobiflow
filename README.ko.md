# dobiflow

> English: [README.md](README.md)

이슈나 작업을 받아 **파악 → GitHub 이슈 → 승인 → 구현 루프(구현→검증→자가체크) → PR**까지
로컬에서 자동으로 굴리는 Claude Code / Codex 플러그인.

버그든 기능이든 한 줄 던지면 알아서 분류하고, 코드 원인/설계를 파악해
GitHub 이슈를 만들고, 네가 승인하면 브랜치 따서 고치고 PR까지 올린다.
전부 **로컬 실행**(GitHub Actions 안 씀) — Claude Code / Codex 구독으로 굴러가니 API 추가 비용 0.

## 설치

### Claude Code (플러그인)

```bash
# 마켓플레이스 등록 후 설치
/plugin marketplace add NariP/dobiflow
/plugin install dobiflow@dobiflow
```

로컬에서 바로 테스트:
```bash
claude --plugin-dir <클론 경로>
```

### Claude Code + Codex CLI (스크립트)

클론 후 `install.sh` 하나면 설치된 CLI(claude/codex)를 자동 감지해 각 홈에 설치한다.

```bash
git clone https://github.com/NariP/dobiflow
cd dobiflow
./install.sh              # claude·codex 둘 다 (감지된 것만)
# ./install.sh --claude-only / --codex-only / --dry-run
```

| 대상 | 설치 위치 |
|------|----------|
| Claude | `~/.claude/skills/*`, `~/.claude/agents/*.md` |
| Codex | `~/.agents/skills/*` + `~/.codex/skills/*` (버전 호환), `~/.codex/agents/*.toml` |

> Codex에서 Serena LSP를 쓰려면 `~/.codex/config.toml`에 `[mcp_servers.serena]`를 등록한다(선택 — 없으면 grep으로 동작).

## 빠른 시작

```
1.  /triage-init      ← 새 프로젝트에서 딱 1번 (설정 자동 생성)
2.  /work <할 일>      ← 평소엔 이것만. 버그든 기능이든 던지면 알아서 분류
3.  "ㅇㅋ"             ← 만든 이슈/설계 보고 승인하면 → PR까지 자동
```

까먹으면 `/triage-help`.

## 명령어

| 명령 | 역할 |
|------|------|
| `/work` | 입구 — 입력 보고 버그/기능 분류 → 알맞은 워크플로우로 |
| `/triage-fix` | 버그 — 원인 파악 → 이슈 → 수정 → PR |
| `/task-run` | 기능/개선/리팩토링 — 설계 → 이슈 → 구현 → PR (큰 작업은 plan mode) |
| `/triage-status` | 열린 이슈·진행 PR 현황 조회 (조회만) |
| `/triage-init` | 새 프로젝트 설정 생성 (레포·린트·정책문서·커밋규칙·계정 감지) |
| `/triage-help` | 사용법 안내 |

## 동작 방식

```
/work 대시보드 로고 눌렀는데 안 감
   ├─ 분류        → 버그 → triage-fix
   ├─ 원인 파악    → issue-triage (읽기 전용)
   ├─ GitHub 이슈  → 생성 + URL 보고
   ├─ ✋ 승인       → 레포·계정 확인 후 "고칠까요?"
   ├─ 구현 루프 🔁  → implementer 에이전트가 구현 + 린트·테스트
   │                 → policy-checker + code-reviewer (병렬)
   │                 → ❌ 지적 나오면 자동 재구현 (최대 3회, 설정 가능)
   └─ PR          → 그린 후 커밋 + 생성 + 리뷰어 + URL
```

자세히는 [`docs/triage-workflow-guide.md`](docs/triage-workflow-guide.md).

## 동작 조건과 한계 (꼭 읽기)

dobiflow는 전부 **네 컴퓨터에서** 돌아가므로 몇 가지 조건이 필요하다:

- **대상 레포가 로컬에 클론돼 있어야 한다.** 라우팅은 클론된 레포들 중에서 고른다.
  레포가 컴퓨터에 없으면 "클론 후 다시 시도"라고 안내하고 멈춘다 — 임의로 클론하지 않는다.
- **코드 작업(버그/기능/리팩)용이다.** 분류는 제목이 아니라 **요구사항 전체**를 읽는다 —
  팝업·버튼·링크 연결·"다시 보지 않음" 같은 구현 항목이 하나라도 있으면, 제목이 "약관/정책"이라도
  기능 작업으로 본다. **코드 작업이 전혀 없는** 순수 법무 텍스트·문서·운영만 범위 밖이고,
  섞여 있으면 나눠서(코드 부분은 진행, 비-코드 부분은 알림) 처리한다.
- **약한 라우팅 매치는 자동 진행 안 함.** 어느 레포인지 애매하면 물어본다.
- **쓰기는 게이트를 통과해야 한다.** 이슈/PR 만들기 직전 active GitHub 계정을 재확인하고
  (엉뚱한 계정으로 올리는 것 방지), 코드를 건드리기 전 네 승인을 받는다.

## 특징

- **Claude Code + Codex 둘 다** — 같은 워크플로우를 두 CLI에서 (스킬·서브에이전트·plan mode 네이티브 대응)
- **입력 자유** — 노션 링크 / 슬랙 링크 / 그냥 텍스트 다 받음
- **승인 정지점** — 이슈는 만들되, 코드는 네가 "ㅇㅋ" 해야 손댐
- **멀티 레포** — 이슈 내용 보고 알맞은 레포 자동 판단 (애매하면 물어봄)
- **멀티 계정** — 레포마다 다른 GitHub 계정. 쓰기 직전 계정 재확인(오발송 방지)
- **프로젝트 룰 우선** — 커밋 규칙·정책·컨벤션을 그 프로젝트 것으로
- **구현 루프** — 구현은 implementer 에이전트, 검사는 리뷰 에이전트들이 맡아 지적이 나오면
  자동 재구현. 그린이 될 때까지 돌되 한도를 넘기면 억지 PR 대신 멈추고 보고
- **자가체크 분리** — 도메인 정책 검사 + 일반 코드리뷰를 따로 (읽기 전용 에이전트)
- **코드 탐색** — Serena LSP 있으면 심볼 단위 정밀, 없으면 grep 폴백

## 이벤트 훅 (선택)

dobiflow가 GitHub 이슈·PR을 만들면 훅이 발동해서 **네가 정의한 스크립트**를 실행한다 —
슬랙/텔레그램 알림, 로그, 노션 기록, 뭐든.

실행 가능한 스크립트를 아래 위치에 두면 된다(전역·프로젝트 둘 다 가능):

```
~/.dobiflow/hooks/on-issue-created.sh          # 전역 (모든 프로젝트)
~/.dobiflow/hooks/on-pr-created.sh
<repo>/.claude/dobiflow-hooks/on-issue-created.sh   # 프로젝트별
<repo>/.claude/dobiflow-hooks/on-pr-created.sh
```

훅에는 환경변수로 정보가 들어온다: `DOBIFLOW_EVENT`, `DOBIFLOW_URL`,
`DOBIFLOW_COMMAND`, `DOBIFLOW_CWD`. 템플릿은 `hooks/examples/` 참고.
훅이 실패해도 dobiflow 본 작업은 막히지 않는다. (`jq` 필요)

## 의존성 (권장)

- **GitHub CLI (`gh`)** — 이슈/PR 생성. 인증 필요(`gh auth login`).
- **Serena MCP** (선택) — 심볼 단위 코드 탐색. 없으면 grep으로 동작.
  user 스코프 등록: `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code`

## 라이선스

MIT
