---
name: task-run
description: 일반 태스크(기능 추가·개선·리팩토링) 작업 — 요구 파악 → 알맞은 레포 결정 → 설계 → GitHub 이슈 생성 → 설계 승인 → 브랜치·구현·자가체크·PR. 규모 크면 plan mode 권유. 사용자가 /task-run(또는 /work 라우터) 로 호출할 때만.
argument-hint: <할 일 설명 | 노션·슬랙 링크>
disable-model-invocation: true
---

# task-run — 일반 태스크(기능/개선) 파악부터 PR까지

버그가 아니라 **새 기능·개선·리팩토링** 같은 일반 작업을 처리한다. 입력: `$ARGUMENTS`

`triage-fix`(버그)와 뼈대·설정은 같되, **"원인 파악" 대신 "설계"가 중심**이다.
버그는 원인이 정답을 정하지만, 일반 태스크는 여러 방법이 있어 **설계 합의가 먼저**다.

> 전역 스킬. 프로젝트 고유값은 `<repo>/.claude/triage.config.json`에서 읽는다(없으면 `/triage-init` 권장).

---

## 진행 순서

### 0단계 — 설정 로드
`triage-fix`와 동일. cwd(또는 라우팅된 레포)의 `triage.config.json`(+`.local.json`) 읽기.
없으면 fallback(repo=git remote, default_branch=main, lint 감지, label_prefix="", 계정 전환 안 함). 핵심값: `repo`, `default_branch`, `lint_command`, `convention_doc`, `tech_stack`, `commit_convention`, `branch_prefix`, `codeowners`, `account`, `git_identity`, `serena`, `policy_docs`.

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
- 아래 **이슈 템플릿**으로 생성. 제목: `{label_prefix}` + 원본. 라벨: `enhancement`/`feature`(레포에 있으면, 없으면 라벨 생략 또는 기본).
- 멀티계정 시퀀스(§) 적용해 `GH_TOKEN=... gh issue create --repo {repo}`.
- **설계안을 보여주고 승인받는다** (버그보다 이 단계가 더 중요 — 방향이 갈리므로):
  > "이슈 #N 만들었어요: <전체 URL>
  >  레포: {repo} / 계정: {account} / base: {default_branch}
  >  이렇게 설계했는데 이 방향으로 구현할까요?"
- 명시적 승인 전 코드 수정 금지. 방향 바꾸자면 반영 후 재확인.
- ⚠️ **범위·방법을 물어본 답은 "승인"이 아니다.** 1·3단계에서 AskUserQuestion으로 범위/접근을
  물어 답을 받았어도 그건 *설계 합의*일 뿐. **반드시 이 4단계의 "이대로 구현할까요?"에 대한
  명시적 OK를 별도로 받아야** 5단계(구현)로 간다. 중간 질문 답을 승인으로 착각해 직행 금지.

### 5단계 — 브랜치 + 구현
- `{default_branch}`에서 `{branch_prefix.feat}<슬러그>`(기본 `feat/`). 리팩토링이면 적절한 prefix.
- 설계대로 구현. 편집 전 Read. **기존 패턴·컨벤션 준수**(새 추상화 남발 금지). 수정 후 `{lint_command}`.

### 5.5단계 — 자가체크 (policy-checker + code-reviewer, 병렬, 읽기 전용)
`triage-fix`와 동일. `{policy_docs}`·`{convention_doc}`·`{tech_stack}`·`{serena}` 전달.
❌위반이면 멈추고 수정 후 재검사. ⚠️주의는 PR 셀프체크에 기록.

### 6단계 — 커밋 + PR
- 커밋: **`{commit_convention}` 최우선**(없으면 Conventional Commits). 보통 `feat:`/`refactor:`/`chore:`. **Co-Authored-By 금지.** author는 `{git_identity}` 커밋 단위 주입.
- 멀티계정 시퀀스로 push·PR. base `{default_branch}`. `Closes #N`.
- 리뷰어: `{codeowners}` 기준(작성자 제외, 없으면 생략).
- 이슈·PR **전체 URL을 클릭 가능하게** 보고.

---

## 멀티계정 시퀀스 (오발송 방지)
`triage-fix`와 **완전히 동일**. 쓰기 직전에만, `{account}`가 active와 다를 때만:
```
TOKEN=$(gh auth token --user {account})
WHO=$(GH_TOKEN="$TOKEN" gh api user -q .login)   # == {account} 게이트, 불일치 중단
GH_TOKEN="$TOKEN" gh issue create / pr create --repo {repo} ...
```
push는 `git -c http.extraHeader="AUTHORIZATION: bearer $TOKEN" push`. 토큰 로깅 금지.

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
- 정책: <policy-checker 요약>
- 코드: <code-reviewer 요약>

## 리뷰 포인트
- [ ] <확인할 것>

---
🤖 자동 생성됨
```

> 문구는 자연스러운 한국어로.

---

## 가드
- **4단계 설계 승인 전 코드 수정 금지.** 이슈 생성까지만 OK.
- ⚠️ **"수정해줘/만들어줘" 같은 직접 명령이 입력에 있어도 이슈 생성·설계 승인을 건너뛰지 않는다.** 직접 명령 = "처리해달라"지 "절차 생략"이 아니다.
- **읽기/파악은 issue-triage 위임.** 기존 패턴 먼저 찾고 재사용(새로 짜기 전에).
- **커밋은 프로젝트 룰(`commit_convention`) 우선. Co-Authored-By 금지.**
- **큰 작업은 plan mode 권유** — 설계 합의 없이 큰 구현 들어가지 않는다.
- **오발송 방지** — `gh api user` 게이트, 레포·계정 합동 확인, 토큰 로깅 금지.
- 약한 라우팅 매치 자동 진행 금지.
- 전부 로컬 실행(GitHub Actions 안 씀).
