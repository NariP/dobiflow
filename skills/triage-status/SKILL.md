---
name: triage-status
description: triage 작업 현황 조회 — 열린 이슈와 진행 중 PR을 한눈에. 조회 전용(수정 안 함). 사용자가 /triage-status 로 명시 호출할 때만.
disable-model-invocation: true
---

# triage-status — triage 작업 현황 조회 (범용)

`/triage-fix`로 처리 중인 것들을 한눈에 보여주는 **조회 전용** 스킬. 코드를 고치거나
이슈/PR을 만들지 않는다. 무엇이 떠 있고 무엇이 안 끝났는지 파악용.

> 전역 스킬. 레포·접두사는 cwd의 `.claude/triage.config.json`에서 읽는다.

## 동작

0. **설정 로드**: cwd의 `.claude/triage.config.json` 읽어 `{repo}`, `{label_prefix}`,
   `{branch_prefix}` 확보. 없으면 `{repo}` = `git remote get-url origin` 자동 감지,
   `{label_prefix}` = `""`.
1. **열린 이슈** 조회:
   ```bash
   gh issue list --repo {repo} --state open --limit 20 \
     --json number,title,labels,url
   ```
2. **열린 PR** 조회:
   ```bash
   gh pr list --repo {repo} --state open --limit 20 \
     --json number,title,headRefName,url
   ```
3. 둘을 묶어 아래 형식으로 표시한다. **`{label_prefix}` 접두사 이슈**(빈 값이면 전체) /
   **`{branch_prefix}` 브랜치 PR**(기본 `fix/`·`feat/`)을 triage 산출물로 보고 우선 보여준다.

## 출력 형식

```
## 🐞 열린 이슈 (N개)
- #N <제목>  (<라벨>)
  <전체 issue URL>
- ...

## 🔀 진행 중 PR (N개)
- #N <제목>  [<브랜치명>]
  <전체 PR URL>
- ...

## 💡 이어가기
- "끝나지 않은 것"(이슈는 있는데 연결된 PR 없음, 또는 PR이 머지 안 됨)을 짚어준다.
- 특정 작업을 이어가려면: 해당 브랜치로 체크아웃(`git checkout <branch>`)하거나,
  새 수정이면 `/triage-fix`로 다시.
```

## 가드

- **조회 전용** — `gh issue create`/`gh pr create`/코드 편집 절대 금지.
- URL은 항상 클릭 가능한 전체 형태로 표시 (`#N`만 쓰지 말 것).
- "대화 세션" 자체를 이어가는 건 Claude Code 기본 기능(`claude --resume` / `--continue`)이지
  이 스킬이 아니다 — 사용자가 세션 resume을 물으면 그걸 안내한다.
