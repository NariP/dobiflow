# Triage 워크플로우 가이드

> 이슈/작업을 받아 **파악 → GitHub 이슈 → 승인 → 수정 → 자가체크 → PR**까지
> 로컬에서 자동으로 굴리는 전역 도구 모음. 어느 프로젝트에서나 쓸 수 있다.

---

## 🚀 빠른 시작 (3단계)

```
1.  /triage-init      ← 새 프로젝트에서 딱 1번 (설정 자동 생성)
2.  /work <할 일>      ← 평소엔 이것만. 버그든 기능이든 던지면 알아서 분류
3.  "ㅇㅋ"             ← 만든 이슈/설계 보고 승인하면 → PR까지 자동
```

처음 쓰는 프로젝트면 **`/triage-init` 먼저**. 그다음부턴 `/work`만 기억하면 된다.

---

## 📋 명령어 한눈에

| 명령 | 언제 | 무엇을 |
|------|------|--------|
| **`/work`** | 뭘 할지 정해졌을 때 (대부분) | 입력 보고 버그/기능 분류 → 알맞은 워크플로우로 |
| `/triage-fix` | 버그인 게 확실할 때 | 원인 파악 → 이슈 → 수정 → PR |
| `/task-fix` | 기능 추가·개선·리팩토링 | 설계 → 이슈 → 구현 → PR |
| `/triage-status` | 지금 뭐가 떠 있나 보고 싶을 때 | 열린 이슈·진행 PR 목록 (조회만) |
| `/triage-init` | 새 프로젝트 처음 / 설정 갱신 | `.claude/triage.config.json` 생성 |

> 💡 **`/work` 하나로 충분.** `/triage-fix`·`/task-fix`를 직접 부를 수도 있지만,
> 헷갈리면 그냥 `/work`에 던지면 알아서 보낸다.

---

## 🔤 입력은 뭐든 OK

세 가지 다 받는다:
- **노션 링크** — QA 페이지 URL → 자동으로 내용 읽음
- **슬랙 링크** — 메시지/스레드 URL → 자동으로 읽음
- **그냥 텍스트** — "대시보드에서 로고 눌렀는데 안 감" 처럼 말로 설명

예시:
```
/work https://notion.so/...QA페이지...
/work 후보지 비교 표에 정렬 기능 추가해줘
/triage-fix 로그인하면 흰 화면 떠
```

---

## 🔄 전체 흐름 (버그 예시)

```
/work 대시보드 로고 눌렀는데 안 감
   │
   ├─ 1. 분류        → "버그 같아요, triage-fix로 진행"
   ├─ 2. 원인 파악    → issue-triage가 코드 추적 (Serena LSP / grep)
   ├─ 3. GitHub 이슈  → 생성 + 전체 URL 보고
   ├─ 4. ✋ 승인       → "이슈 #N 만들었어요: <URL> / 레포·계정 확인 / 고칠까요?"
   │                     ← 너가 "ㅇㅋ"
   ├─ 5. 수정         → 브랜치 따서 최소 수정 + 린트
   ├─ 5.5 자가체크    → 정책(policy-checker) + 코드품질(code-reviewer) 병렬 검사
   └─ 6. PR          → 생성 + 리뷰어 지정 + 전체 URL 보고
```

**기능(task-fix)은 2·4단계가 다름:** "원인 파악" 대신 **"설계"**, 승인도
"이렇게 만들까요?"(방향 합의). 큰 작업이면 **plan mode**를 권한다.

---

## ✋ 승인 정지점 (안심 포인트)

- **이슈는 만들어지지만**, 그다음 **코드는 너가 "ㅇㅋ" 해야** 손댄다.
- 승인 전엔 절대 수정 안 함. 방향이 틀렸으면 그때 고쳐 말하면 된다.
- 이슈/PR 보고할 때 **레포·계정·base 브랜치를 같이** 보여줌 (엉뚱한 데 올라가는 것 방지).

---

## ⚙️ 설정 (`/triage-init`이 자동 생성)

프로젝트마다 `.claude/triage.config.json`에 그 프로젝트 고유값이 들어간다:
- 레포명, 기본 브랜치, 린트 명령, 테스트 명령
- 정책 문서 목록, 컨벤션 문서, 기술 스택, 아키텍처
- **커밋 규칙** (그 프로젝트 방식 우선 — Conventional이든 gitmoji든 한글이든)
- 라벨/브랜치 접두사, CODEOWNERS 유무, Serena 사용 여부
- (민감값은 `.local.json`에 분리: GitHub 계정, git 이름/이메일 — gitignore됨)

전부 `/triage-init`이 **자동 감지** + 계정 같은 위험한 값만 한 번 물어본다.
나중에 바뀌면 `/triage-init` 다시 돌리면 갱신(기존 설정은 보존).

---

## 🧩 특징

- **전부 로컬 실행** — GitHub Actions 안 씀. 이슈/PR만 GitHub에, 파악·수정은 네 컴퓨터에서.
  (Claude Code 구독으로 동작, API 추가 비용 0)
- **멀티 레포** — 이슈 내용 보고 알맞은 레포 자동 판단 (애매하면 물어봄).
- **멀티 계정** — 레포마다 다른 GitHub 계정. 쓰기 직전 계정 재확인(오발송 방지).
- **코드 탐색** — Serena LSP(심볼 단위 정밀) 있으면 쓰고, 없으면 grep으로 폴백.
- **자가체크 분리** — 도메인 정책 검사(policy-checker)와 일반 코드리뷰(code-reviewer)를 따로.

---

## ❓ FAQ

**Q. `/work`랑 `/triage-fix`랑 뭐가 달라?**
`/work`는 입구(분류기). 버그면 `/triage-fix`, 기능이면 `/task-fix`로 자동으로 보낸다.
어디로 갈지 알면 직접 불러도 되고, 모르면 `/work`.

**Q. 새 프로젝트에서 `/work` 했더니 이상해.**
`/triage-init`을 안 했을 가능성. 먼저 `/triage-init`으로 설정을 만들자.
(설정 없어도 기본값으로 동작은 하지만, 레포·계정·커밋 규칙이 안 맞을 수 있음.)

**Q. 만든 이슈/PR 어디서 봐?**
보고할 때 **클릭 가능한 전체 URL**을 준다. 현황을 다시 보려면 `/triage-status`.

**Q. 큰 기능이라 설계부터 하고 싶은데?**
`/task-fix`(또는 `/work`)가 규모가 크다고 판단하면 **plan mode**를 권한다.
plan mode에선 계획서를 먼저 쓰고 너 승인 후 구현.

**Q. 커밋 메시지 형식은?**
그 프로젝트 규칙을 따른다(`/triage-init`이 감지). Co-Authored-By는 절대 안 붙인다.

**Q. 이미 처리하던 작업 이어가려면?**
대화 세션은 Claude Code 기본 `claude --resume` / `--continue`.
GitHub에 쌓인 작업은 `/triage-status`로 목록 확인 후 해당 브랜치 체크아웃.

---

## 📂 구성 (참고)

플러그인 `triage-flow` 안에:
```
skills/   work · triage-fix · task-fix · triage-status · triage-init · triage-help
agents/   issue-triage · policy-checker · code-reviewer  (전부 읽기 전용)
docs/     triage-workflow-guide.md  (이 가이드)
```

각 프로젝트엔 설정만 생성된다 (`/triage-init`이 만듦):
```
<프로젝트>/.claude/
  ├── triage.config.json       # 프로젝트 설정
  └── triage.config.local.json # 계정 등 민감값 (gitignore)
```
