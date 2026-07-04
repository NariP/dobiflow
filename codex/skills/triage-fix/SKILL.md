---
name: triage-fix
description: 이슈(노션/슬랙 링크·텍스트) → 알맞은 레포 결정 → 원인 파악 → GitHub 이슈 생성 → 승인 → 구현 루프(implementer 구현→검증→자가체크 반복)·PR. 사용자가 /triage-fix 로 명시 호출할 때만 실행 (수동 전용).
argument-hint: <노션링크 | 슬랙링크 | 이슈 설명 텍스트>
---

# triage-fix — 이슈 파악부터 PR까지 (범용)

입력으로 받은 이슈를 파악해 **알맞은 레포에 GitHub 이슈를 만들고**, 사용자 승인 후
**브랜치를 따서 수정하고 PR까지** 올리는 워크플로우. 입력: `$ARGUMENTS`

입력은 노션 링크 / 슬랙 링크 / 그냥 텍스트 무엇이든 될 수 있다. 소스를 읽어 내용을 파악한다.

> 이 스킬은 **전역**이다. 프로젝트 고유값(레포·정책문서·린트·계정 등)은 각 프로젝트의
> `.claude/triage.config.json`에서 읽는다. 설정 파일은 `/triage-init`으로 생성한다.

---

## 진행 순서 (이 순서를 지킬 것)

### 0단계 — 설정 로드
- 대상 레포가 정해지면 그 레포의 `<repo>/.claude/triage.config.json`(+`triage.config.local.json`)을 읽는다.
- 아직 레포 미정이면 1단계 후 1.5단계(레포 결정)에서 정한다. 현재 cwd가 작업 대상이면 cwd의 config를 먼저 읽어도 된다.
- **config가 없으면 fallback**으로 동작 + "설정 없음 — `/triage-init` 권장" 한 줄 안내:
  - `repo` = `git remote get-url origin` 자동 감지
  - `default_branch` = `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (실패 시 `main`)
  - `lint_command` = package.json scripts 감지 (`lint:fix`>`lint`>`format`), 없으면 생략
  - `policy_docs` = `.claude/docs/*.md` 글롭 (없으면 빈 목록)
  - `label_prefix` = `""` (접두사 없음)
  - `account` = 미지정 → **계정 전환 안 함**(현재 active gh 계정 그대로)
  - `loop.max_iterations` = 미지정 → `3` (구현 루프 최대 반복)
- 이후 단계에서 `{repo}`, `{default_branch}`, `{lint_command}`, `{policy_docs}`,
  `{label_prefix}`, `{branch_prefix}`, `{bug_label}`, `{codeowners}`, `{account}`,
  `{git_identity}`, `{serena}`, `{convention_doc}`, `{tech_stack}`, `{loop}` 등을 config 값으로 쓴다.

### 1단계 — 소스 읽기
- **노션 링크** (`notion.so` / `notion.com`): `mcp__claude_ai_Notion__notion-fetch`로 페이지 내용 가져오기.
- **슬랙 링크** (`slack.com/archives/...`): Slack MCP로 메시지/스레드 읽기.
- **텍스트만**: 그대로 이슈 설명으로 사용.
- 링크인데 읽기 실패하면 사용자에게 내용 붙여달라고 요청하고 멈춘다 (추측 금지).

### 1.5단계 — 레포 결정 (멀티레포 라우팅)
이슈가 **어느 레포 것인지** 정한다. cwd가 이미 명백한 대상이면 생략 가능.
- **후보 출처**:
  1. (1순위) 로컬 스캔 — 클론된 레포들(작업 루트 하위 디렉토리)의 git remote(`owner/name`) +
     각 레포 `.claude/triage.config.json`의 `repo`/`keywords`.
  2. (보강) 조직 레포 카탈로그 MCP가 있으면 그 설명을 활용. 클론 안 된 레포는 "클론 필요" 안내.
- **매칭**: 이슈 단서(화면명·기능·도메인 키워드) ↔ 후보의 keywords/설명/디렉토리명.
- **약한 매치는 자동 진행 금지** — `AskUserQuestion`으로 top 2~3 후보 제시해 확정받는다.
- 확정 후, **현재 cwd가 그 레포가 아닐 때만 `cd <레포경로>`를 단독으로 1회** 실행해 진입한다(그 레포 config 로드·Serena 컨텍스트 정렬을 위해). **이미 그 레포 안이면 cd 하지 않는다.** cwd는 이후 Bash 호출 간 유지되므로, 진입 후의 명령은 `cd <경로> && ...`로 감싸지 말고 **명령만** 친다 (`cd X && cmd` 형태의 compound 커맨드는 매번 권한 확인을 띄운다).
- **클론 안 된 레포**면 작업 불가 → "클론 후 재시도" 안내(임의 클론 금지).

### 2단계 — 코드 원인 파악 (issue-triage 위임)
- `issue-triage` 서브에이전트에 위임한다. 읽기 전용 조사만 (코드 수정 X).
- **config 값을 함께 전달**: `serena`(LSP 사용 가능 여부), `convention_doc`, `policy_docs`,
  화면 경로/라벨/컴포넌트명 등 단서. `serena=false`면 grep만 쓰라고 알린다.
- 받을 것: 관련 파일:줄, 데이터 흐름, 원인 추정, 수정 지점.

### 3단계 — GitHub 이슈 생성 (먼저 만든다)
- 아래 **이슈 템플릿**으로 본문을 채운다.
- 제목: 원본 제목 + `{label_prefix}` 접두사(빈 값이면 접두사 없음). 라벨: `{bug_label}`(기본 `bug`).
- **멀티계정 시퀀스(§멀티계정) 적용** 후 `GH_TOKEN=... gh issue create --repo {repo} ...`로 생성.
- `gh issue create`는 **전체 URL을 stdout으로 반환**한다. 그 URL을 그대로 확보한다.

### 4단계 — 승인 받기 ✋ (필수 정지점)
- 생성된 **이슈 내용(원인 파악 + 해결 방안)을 사용자에게 보여주고** 묻는다.
- **이슈 생성 보고 시 `gh`가 반환한 전체 URL을 클릭 가능하게 명시**한다(`#N`만 쓰지 말 것).
- **레포·계정·base 브랜치를 한 화면에서 함께 확인**한다 (오발송 방지). 예:
  > "이슈 #N 만들었어요: <전체 URL>
  >  레포: {repo} / 계정: {account} / base: {default_branch}
  >  승인하면 구현 루프(implementer 구현 → lint·테스트 → 자가체크, 최대 {loop.max_iterations}회)로 진행해요.
  >  이 방향으로 수정하고 PR 올릴까요?"
- 사용자가 명시적으로 **OK/ㅇㅋ/진행** 하기 전에는 **절대 코드를 건드리지 않는다.**

### 5단계 — 브랜치 + 구현 루프 🔁

메인 세션은 이 단계에서 **직접 구현하지 않는다** — 루프 컨트롤러 역할만 한다
(반복 관리·판정·loop.md 갱신). 구현은 매 반복 `implementer` 서브에이전트가 한다.

**준비 (루프 진입 전 1회):**
- `{default_branch}`에서 새 브랜치: `{branch_prefix.fix}<짧은-영문-슬러그>` (기본 `fix/`).
- **loop.md 생성**: `<repo>/.claude/loops/<이슈번호>/loop.md` — 아래 **loop.md 템플릿**대로.
  완료 기준은 이슈의 "해결 방안"·"기대 동작"에서 그대로 가져온다 (**루프 중 수정 금지**).
- `.claude/loops/`가 커밋되지 않게 `.git/info/exclude`에 `.claude/loops/` 한 줄 추가(이미 있으면 생략).

**루프 (최대 `{loop.max_iterations}`회, 기본 3):**
1. **구현 — `implementer` 서브에이전트 위임.** 전달할 것: loop.md 경로, 이번 반복 지시
   (1회차 = 이슈의 해결 방안, 2회차부터 = 직전 REQUEST_CHANGES 지적사항),
   config(`convention_doc`·`tech_stack`·`lint_command`·`test_command`·`serena`).
   implementer는 최소 편집으로 구현하고 **lint·테스트까지 통과시켜** 보고한다
   (실패 상태로 완료 보고 금지 — 못 풀면 "막힘"으로 보고).
2. **자가체크 — 서브에이전트 2개 병렬 (읽기 전용).** 변경 파일 목록(또는 `git diff`) 전달.
   - **`policy-checker`** — 도메인 정책 위반. **`{policy_docs}` 목록을 인자로 전달**(비면 "정책 문서 없음" 통과).
   - **`code-reviewer`** — 일반 코드 품질. **`{convention_doc}`+`{tech_stack}`를 전달**(없으면 범용 베스트프랙티스).
   - 둘 다 `{serena}` 값도 전달(false면 grep 폴백).
3. **판정 (메인 세션):**
   - implementer가 **막힘** 보고 → 루프 즉시 중단, 사용자에게 보고 (커밋·PR 없음).
   - ❌ **위반 있음** → **REQUEST_CHANGES**: 지적사항을 loop.md 반복 로그에 기록하고 다음 반복으로.
   - ❌ 없음(⚠️/💡만) → **APPROVE**: ⚠️는 PR "## 셀프체크"용으로 요약해 두고 루프 종료 → 6단계.

- **max 소진 시**: 커밋·PR 없이 중단. WIP 브랜치는 유지하고, 마지막 지적사항 + 뭐가 안 풀리는지
  정리해 사용자에게 보고한다 (계속/방향 전환/직접 확인은 사용자 판단).
- 작은 수정(한두 파일·명백)은 보통 **1바퀴에 APPROVE로 끝난다** — 구조는 같고 반복만 안 생길 뿐.
- **루프 안에서 커밋·push 금지** — APPROVE 후 6단계에서 1회.
- **백엔드 수정이 필요한 부분은 프론트에서 임의로 우회하지 말고** 이슈/PR에 "백엔드 필요"로 남긴다.

### 6단계 — 커밋 + PR (APPROVE 후에만)
- 커밋 메시지: **`{commit_convention}`(그 프로젝트 규칙)을 최우선으로 따른다.**
  config에 `commit_convention`이 있으면 그 rule·examples 형식대로(prefix·언어·이모지 등).
  없으면 Conventional Commits로 폴백. **어느 경우든 `Co-Authored-By` 트레일러 금지.**
  author는 `{git_identity}`가 있으면 `git -c user.name=... -c user.email=... commit`으로 커밋 단위 주입(전역 안 건드림).
- push: **멀티계정 시퀀스(§멀티계정)의 push 방식** 사용.
- `gh pr create` (멀티계정 시퀀스 적용, `GH_TOKEN=...`):
  - 제목: 커밋 제목과 동일. base: `{default_branch}`.
  - 본문: 아래 **PR 템플릿**. `Closes #N`. 원본 노션/슬랙 링크 첨부.
  - **리뷰어**: `{codeowners}`가 경로면 매칭 코드오너에서 **작성자 본인 제외** → 남은 사람만 `--reviewer`.
    남은 사람 없으면 생략. `{codeowners}`가 false면 리뷰어 단계 스킵.
- `gh pr create`가 반환한 **PR 전체 URL을 클릭 가능하게 보고**. 마무리에 이슈 URL·PR URL **둘 다** 명시.
- PR 생성 후 `.claude/loops/<이슈번호>/` **삭제** (loop.md는 일회용 — 기록은 이슈·PR에 남는다).

> **본문 윤문(humanize)은 선택 — 짧은 PR엔 기본 미적용.** 긴 보고/문서일 때만 `/humanize` 수동.

---

## 멀티계정 시퀀스 (오발송 방지 — 쓰기 직전에만)

`{account}`가 비었거나 현재 active gh 계정과 같으면 **전환 안 함**(no-op, 그대로 진행).
다를 때만 아래를 적용. **`GH_TOKEN` 주입** 방식 — 전역 계정 상태를 건드리지 않는다.

```
# 1. 토큰 추출 (로깅 금지)
TOKEN=$(gh auth token --user {account})

# 2. 오발송 게이트 — 쓰기 직전 실제 로그인 == {account} 재확인
WHO=$(GH_TOKEN="$TOKEN" gh api user -q .login)
# WHO != {account} 이면 즉시 중단·사용자 보고 (절대 쓰지 않는다)

# 3. 확정 후에만 쓰기
GH_TOKEN="$TOKEN" gh issue create --repo {repo} ...
GH_TOKEN="$TOKEN" gh pr create   --repo {repo} ...
```

- **git push**: `GH_TOKEN`도 `http.extraHeader="...bearer..."`도 push 인증에 안 먹는다(invalid credentials).
  **URL에 토큰을 끼워** 1회성으로 push한다(remote 설정·전역 상태 안 건드림):
  `git push "https://x-access-token:${TOKEN}@github.com/{repo}.git" <branch>`
  출력에 토큰이 찍힐 수 있으니 `| sed -E "s/${TOKEN}/***/g"`로 마스킹한다.
- **커밋 author**: `{git_identity}`로 커밋 단위 주입(위 6단계).
- **토큰은 절대 로그·출력에 노출하지 않는다.**

---

## 이슈 템플릿 (3단계)

```markdown
## 🐞 문제
<무엇이 잘못됐는지 1~3줄>

## 🔁 재현
**위치:** <화면 경로>
1. <절차>
- 기대: <기대 동작>
- 실제: <문제 동작>

## 🔍 원인 파악 (issue-triage 결과)
- 관련 위치:
  - `path/to/file:line` — <역할>
- 흐름: <진입점 → ... → 문제 지점>
- 원인: <가장 유력한 원인. 추정이면 "추정" 명시>

## 🛠️ 해결 방안
- <어디를 어떻게 고칠지>
- (백엔드 필요 시) <무엇을 백엔드에 요청해야 하는지>

## 출처
- 원본: <노션/슬랙 링크>

---
🤖 자동 생성됨
```

## PR 템플릿 (6단계)

```markdown
## 바뀐 점
<이 PR로 무엇이 달라지는지 1~3줄, 사용자/화면 관점으로>

## 배경
Closes #<이슈번호>
<왜 필요했는지 — 증상/요청 1~2줄>
원본 이슈: <노션/슬랙 링크>

## 작업 내용
- <핵심 변경점, `file:line` 기준으로 한 줄씩>

## 셀프체크 (5단계 루프 결과)
- 루프: <N>회차에 APPROVE
- 정책: <policy-checker 요약>
- 코드: <code-reviewer 요약>

## 리뷰 포인트
- [ ] 로컬에서 <재현 절차>로 동작 확인

---
🤖 자동 생성됨
```

> 문구는 딱딱하지 않게, 읽는 사람이 빠르게 이해할 **자연스러운 한국어**로.

## loop.md 템플릿 (5단계)

```markdown
# 구현 루프 — 이슈 #<N>

- 이슈: <전체 URL>
- 브랜치: <브랜치명>
- 최대 반복: <loop.max_iterations>

## 완료 기준 (이슈에서 복사 — 루프 중 수정 금지)
- [ ] <기대 동작 / 해결 방안 항목>

## 검증 명령
- lint: `<lint_command>` / test: `<test_command>` (없으면 "없음")

## 반복 로그
### 1회차
- 구현: <implementer 보고 요약 1~2줄>
- 판정: APPROVE | REQUEST_CHANGES | 막힘
- 지적사항: <REQUEST_CHANGES일 때 — 다음 회차로 넘기는 것>
```

- loop.md 갱신(반복 로그·체크박스)은 **메인 세션만** 한다. implementer는 읽기만.
- 일회용 파일이다 — PR 후 폴더째 삭제. 영구 기록은 이슈·PR 본문이 담당.

---

## 가드 (어기지 말 것)

- **4단계 승인 전 코드 수정 금지.** 이슈 생성까지는 OK, 그 다음은 정지.
- ⚠️ **"수정해줘/고쳐줘" 같은 직접 명령이 입력에 있어도 이슈 생성·승인을 건너뛰지 않는다.** 그건 "처리해달라"는 뜻이지 "절차 생략"이 아니다.
- **5단계에서 메인 세션 직접 구현 금지** — 구현·수정은 전부 implementer 위임. 메인은 루프 판정·기록만.
- **루프 안 커밋·push 금지** — APPROVE 후 1회. max 소진·막힘이면 커밋 없이 중단·보고.
- **읽기/파악은 issue-triage에 위임** — 메인 대화를 파일 덤프로 더럽히지 않는다.
- **커밋 메시지에 Co-Authored-By 금지** (사용자 규칙).
- **UI 임의 제거/숨김 금지** — 백엔드 미지원이어도 임의로 빼지 않는다.
- **백엔드가 원인인 부분**은 프론트에서 억지로 우회하지 말고 이슈/PR에 명시한다.
- **전부 로컬 실행** — GitHub Actions·자동 트리거 안 씀. 이슈/PR만 GitHub에, 파악·수정은 로컬.
- **오발송 방지** — 멀티계정 시퀀스의 `gh api user` 게이트를 쓰기 직전 반드시 통과. 레포·계정 합동 확인. 토큰 로깅 금지.
- **약한 라우팅 매치는 자동 진행 금지** — 사용자 확인.
