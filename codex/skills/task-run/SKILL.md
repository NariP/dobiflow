---
name: task-run
description: 일반 태스크(기능 추가·개선·리팩토링) 작업 — 요구 파악 → 알맞은 레포 결정 → 설계 → GitHub 이슈 생성 → 설계 승인 → 구현 루프(implementer 구현→검증→자가체크 반복)·PR. 규모 크면 plan mode 권유. 사용자가 /task-run(또는 /work 라우터) 로 호출할 때만.
argument-hint: <할 일 설명 | 노션·슬랙 링크>
---

# task-run — 일반 태스크(기능/개선) 파악부터 PR까지

버그가 아니라 **새 기능·개선·리팩토링** 같은 일반 작업을 처리한다. 입력: `$ARGUMENTS`

`triage-fix`(버그)와 뼈대·설정은 같되, **"원인 파악" 대신 "설계"가 중심**이다.
버그는 원인이 정답을 정하지만, 일반 태스크는 여러 방법이 있어 **설계 합의가 먼저**다.

> 전역 스킬. 프로젝트 고유값은 `<repo>/.claude/triage.config.json`에서 읽는다(없으면 `/triage-init` 권장).

---

## 진행 순서

### 0단계 — 설정 로드
`triage-fix`와 동일. cwd(또는 라우팅된 레포)의 `triage.config.json` 읽기.
없으면 fallback(repo=git remote, default_branch=main, lint 감지, label_prefix="", loop.max_iterations=3, loop.full_verify_command 없음). 핵심값: `repo`, `default_branch`, `lint_command`, `test_command`, `convention_doc`, `tech_stack`, `commit_convention`, `branch_prefix`, `codeowners`, `serena`, `policy_docs`, `loop`.

### 1단계 — 요구 읽기
입력(텍스트/노션/슬랙)에서 **무엇을 만들/바꿀지** 파악. 모호하면 사용자에게 구체화 질문(추측 금지).

### 1.5단계 — 레포 결정 (멀티레포 라우팅)
`triage-fix`와 동일. 어느 레포 작업인지 확정(약한 매치 자동 금지 → 확인). **현재 cwd가 그 레포가 아닐 때만 `cd <레포경로>`를 단독으로 1회** 실행해 진입(이미 그 레포면 cd 안 함) → 그 레포 config. 진입 후의 명령은 `cd <경로> && ...`로 감싸지 말고 명령만 친다(compound cd는 매번 권한 확인을 띄움).

### 2단계 — 관련 코드·영향 범위 파악 (issue-triage 위임)
- `issue-triage`에 위임(읽기 전용). 단 버그가 아니라 **"이 기능을 넣으려면 어디를 건드려야 하나 + 기존 패턴이 뭔가 + 영향 범위"**를 묻는다.
- config(`serena`, `convention_doc`, `tech_stack`) 전달. 기존에 비슷한 구현·재사용할 유틸이 있는지 우선 찾게 한다(새로 짜기 전에).

### 3단계 — 설계 (규모 따라 plan mode 자동)
- **작은 작업**(한두 파일, 명백한 구현): 간단한 설계안(무엇을 어디에 어떻게)을 정리.
- **큰 작업**(여러 파일·아키텍처 결정·여러 접근법): **plan mode 권유** — "이건 설계가 필요해 보여요, plan mode로 갈까요?" 하고, 동의 시 EnterPlanMode로 계획서 작성.
- 설계엔 기존 패턴 재사용·config의 tech_stack·아키텍처를 반영한다.

### 4단계 — GitHub 이슈 생성 + 설계 승인 ✋ (필수 정지점)
- **메인이 작성**: 아래 **이슈 템플릿**으로 본문·제목(`{label_prefix}` + 원본)·라벨(`enhancement`/`feature`, 없으면 생략) 확정.
- **git-writer 위임**으로 생성: 완성값(`repo={repo}`·`issue_title`·`issue_body`·`labels`)만 넘기면
  `gh issue create` 실행 후 **URL만 반환**(장황한 출력은 서브에 갇힘). 반환 URL 확보(§git-writer 위임).
- **설계안을 보여주고 승인받는다** (버그보다 이 단계가 더 중요 — 방향이 갈리므로):
  > "이슈 #N 만들었어요: <전체 URL>
  >  레포: {repo} / base: {default_branch}
  >  승인하면 구현 루프(implementer 구현 → lint·테스트 → 자가체크, 최대 {loop.max_iterations}회)로 진행해요.
  >  이렇게 설계했는데 이 방향으로 구현할까요?"
- 명시적 승인 전 코드 수정 금지. 방향 바꾸자면 반영 후 재확인.
- ⚠️ **범위·방법을 물어본 답은 "승인"이 아니다.** 1·3단계에서 범위/접근을 물어 답을 받았어도
  그건 *설계 합의*일 뿐. **반드시 이 4단계의 "이대로 구현할까요?"에 대한 명시적 OK를 별도로
  받아야** 5단계로 간다. 중간 질문 답을 승인으로 착각해 직행 금지.

### 5단계 — 브랜치 + 구현 루프 🔁
구조·loop.md 템플릿은 `triage-fix` 5단계와 **동일** — 메인 세션은 루프 컨트롤러만
(직접 구현 금지), 구현은 매 반복 `implementer` 서브에이전트가. task-run 고유 사항:
- **준비**: 브랜치 `{branch_prefix.feat}<슬러그>`(기본 `feat/`, 리팩토링이면 적절한 prefix).
  `<repo>/.claude/loops/<이슈번호>/loop.md` 생성 — 완료 기준은 이슈의 **"✅ 완료 기준"** 체크리스트를
  그대로 복사 (루프 중 수정 금지). **"관련 위치"에는 이슈 "📐 설계"의 변경 범위 + 2단계
  issue-triage가 반환한 파일:줄 원본을 직접 복사** (이슈 본문은 요약이라 깎일 수 있으니 issue-triage 반환 전문을
  넣는다 — 메인이 이미 갖고 있어 추가 토큰 0, implementer 재탐색 방지). `.git/info/exclude`에 `.claude/loops/` 추가.
  준비가 끝나면 **이벤트 발행**: `work-started` — 인자 `branch=<브랜치명> title="<이슈 제목>" issue_url=<이슈 전체 URL>` (§이벤트 발행).
- **루프 (최대 `{loop.max_iterations}`회, 기본 3):**
  1. `implementer` 위임 — loop.md 경로 + 이번 반복 지시(1회차 = 4단계에서 승인된 **설계**,
     2회차부터 = 직전 지적사항) + config(`convention_doc`·`tech_stack`·`lint_command`·`test_command`·`serena`).
     **기존 패턴·컨벤션 준수**(새 추상화 남발 금지)를 지시에 명시. lint·테스트 통과가 완료의 전제.
  2. 자가체크 — `policy-checker`+`code-reviewer` 병렬(읽기 전용). `{policy_docs}`·`{convention_doc}`·`{tech_stack}`·`{serena}` 전달.
     **변경 파일 경로 목록만 전달**한다(implementer 보고의 "변경 파일" 필드). **`git diff` 전문을
     프롬프트에 넣지 말 것** — diff가 필요하면 checker가 자기 Read로 해당 파일을 연다(컨텍스트 절약).
     **1회차 = 전체 검사, 2회차부터 = 재검증 모드** — 직전 지적사항 + 이번 회차 **변경 파일 경로**만
     전달해 "지적 해소 여부 + 변경의 새 위반"만 본다 (풀 리체크 금지).
  3. 판정 — ❌위반 = **REQUEST_CHANGES**(지적사항 loop.md 기록 후 재위임) / ⚠️뿐이어도 실질 회귀·
     데이터 손실·보안 노출이면 ❌로 승격 가능(사유 loop.md 기록) / ❌없음 = **APPROVE** —
     `{loop.full_verify_command}` 있으면 여기서 1회 실행(풀 빌드 등, 실패 시 REQUEST_CHANGES로
     다음 반복), 통과하면 ⚠️는 PR 셀프체크에 기록하고 6단계로 / implementer **막힘** = 중단·보고.
     판정을 loop.md에 기록한 직후 **이벤트 발행**: `iteration-completed` — 인자
     `iteration=<회차> verdict=<approve|request_changes|blocked>` (§이벤트 발행).
- max 소진 시 커밋·PR 없이 중단·보고(WIP 브랜치 유지). **루프 안 커밋·push 금지.**
- 루프 중단 시(막힘·max 소진) 보고 전에 **이벤트 발행**: `work-stopped` — 인자 `reason=<blocked|max-iterations>` (§이벤트 발행).

### 6단계 — 커밋 + PR (APPROVE 후에만 · git-writer 위임)
**메인이 판단·작성**하고 실행은 git-writer가 한다.
- **메인이 작성**: 커밋 메시지(**`{commit_convention}` 최우선**, 없으면 Conventional Commits — 보통 `feat:`/`refactor:`/`chore:`, **Co-Authored-By 금지**), PR 제목/본문(`Closes #N`), 리뷰어 목록(`{codeowners}` 기준·작성자 제외·없으면 빈 목록), 스테이징 지시(보통 `all`).
- **git-writer 위임**: 위 완성값 + `repo={repo}`·`branch`·`base_branch={default_branch}`를 넘긴다.
  git-writer가 `add→commit→push→gh pr create` 실행, **PR URL만 반환**. author는 현재 git 설정 그대로.
  git-writer는 log/diff/코드를 읽지 않는다(메인이 다 완성해 넘겼으므로). 실패 보고 시 억지 재시도 없이 사용자에게.
- 반환된 이슈·PR **전체 URL을 클릭 가능하게** 보고. PR 후 `.claude/loops/<이슈번호>/` 삭제(일회용).
- **이벤트 발행**: `work-finished` — 인자 `pr_url=<PR 전체 URL> iterations=<총 회차>` (§이벤트 발행).

---

## git-writer 위임 (쓰기 실행)
`triage-fix`와 동일. 이슈 생성(4단계)·커밋+PR(6단계)의 **실행**은 `git-writer` 서브에이전트가 한다 —
`git log`/`diff`/`gh` 출력을 메인에 쌓지 않고 서브에 가둬 **컨텍스트를 아낀다**.
- **메인이 판단·작성**(커밋 메시지·PR 본문·리뷰어·스테이징 결정), **git-writer는 실행만**.
  git-writer는 코드·log·diff를 읽지 않는다 — 완성값을 메인이 넘겼으므로.
- 넘기는 값: (이슈) `repo`·`issue_title`·`issue_body`·`labels` / (PR) `repo`·`branch`·`base_branch`·`commit_message`·`pr_title`·`pr_body`·`reviewers`·`stage`. 받는 값: URL만.

## GitHub 계정 (참고)
dobiflow는 **현재 로그인된 gh 계정과 현재 git 설정을 그대로 신뢰**한다.
계정 전환·멀티계정은 dobiflow 밖(예: `gitto`)에서 처리 — git-writer가 인증 주입 없이 평범하게 실행한다.

## 이슈 템플릿 (4단계)

```markdown
## 🎯 목표
<무엇을 만들/바꾸는지 1~3줄>

## 📐 설계
- 접근: <어떻게 — 핵심 방식>
- 변경 범위: `path/...` (재사용할 기존 패턴/유틸이 있으면 명시)
- (대안 있었으면) 왜 이 방식인지 한 줄

## ✅ 완료 기준
- [ ] <이게 되면 끝>

## 출처
- 원본: <링크 또는 텍스트>

---
🤖 자동 생성됨
```

## PR 템플릿 (6단계)
```markdown
## 바뀐 점
<이 PR로 무엇이 생기/달라지는지, 사용자/화면 관점>

## 배경
Closes #<이슈번호>
<왜 필요한지 1~2줄>

## 작업 내용
- <핵심 변경, `file:line`>

## 셀프체크
- 루프: <N>회차에 APPROVE
- 정책: <policy-checker 요약>
- 코드: <code-reviewer 요약>

## 리뷰 포인트
- [ ] <확인할 것>

---
🤖 자동 생성됨
```

> 문구는 자연스러운 한국어로.

---

## 이벤트 발행 (선택 — 외부 수집·알림용)

`triage-fix`와 동일한 구조. 5·6단계의 지정 시점마다 아래 한 줄을 실행:

```
~/.dobiflow/bin/dobiflow-emit <event> skill=task-run repo={repo} issue=<이슈번호> <시점별 추가 인자>
```

- 이벤트 4개: `work-started`(루프 진입) → `iteration-completed`(매 반복 판정) →
  `work-finished`(PR 생성) 또는 `work-stopped`(막힘·max 소진 중단).
- **루프 진입 전 존재 확인 1회**: `test -x ~/.dobiflow/bin/dobiflow-emit` — 없으면(미설치)
  이번 작업의 모든 발행을 조용히 생략한다.
- **부가기능이다** — 발행이 실패해도 무시하고 본 작업을 계속한다. 재시도·디버깅·별도 보고 금지.

---

## 말투
사용자 대면 **진행 보고·정지점·완료 알림**은 **도비 톤**으로 한다.
규칙·단계별 예시·적용 범위(이슈/PR 본문·loop.md·서브 프롬프트엔 톤 미적용)는
`references/dobi-persona.md`를 따른다(필요 시 읽는다).
톤은 표현일 뿐 아래 가드·정지점·위임 규칙을 바꾸지 않는다.

## 가드
- **4단계 설계 승인 전 코드 수정 금지.** 이슈 생성까지만 OK.
- ⚠️ **"수정해줘/만들어줘" 같은 직접 명령이 입력에 있어도 이슈 생성·설계 승인을 건너뛰지 않는다.** 직접 명령 = "처리해달라"지 "절차 생략"이 아니다.
- **5단계에서 메인 세션 직접 구현 금지** — 구현·수정은 전부 implementer 위임. 메인은 루프 판정·기록만.
- **루프 안 커밋·push 금지** — APPROVE 후 1회. max 소진·막힘이면 커밋 없이 중단·보고.
- **읽기/파악은 issue-triage 위임.** 기존 패턴 먼저 찾고 재사용(새로 짜기 전에).
- **커밋은 프로젝트 룰(`commit_convention`) 우선. Co-Authored-By 금지.**
- **큰 작업은 plan mode 권유** — 설계 합의 없이 큰 구현 들어가지 않는다.
- **오발송 방지** — 쓰기 직전 대상 레포 재확인. 계정은 현재 gh 로그인 상태 신뢰(멀티계정은 dobiflow 밖).
- 약한 라우팅 매치 자동 진행 금지.
- 전부 로컬 실행(GitHub Actions 안 씀).
