---
name: triage-help
description: triage 워크플로우(work/triage-fix/task-run/triage-status/triage-init) 사용법을 안내한다. "어떻게 쓰지?" 싶을 때. 사용자가 /triage-help 로 호출할 때만.
disable-model-invocation: true
---

# triage-help — 사용법 안내

`${CLAUDE_PLUGIN_ROOT}/docs/triage-workflow-guide.md`를 Read해서 사용자에게 **핵심을 요약**해 보여준다.
인자가 있으면(예: `/triage-help 승인`) 그 주제 부분만 발췌해 설명한다.

## 동작
1. `${CLAUDE_PLUGIN_ROOT}/docs/triage-workflow-guide.md`를 Read.
2. 인자 없으면: "빠른 시작 3단계" + "명령어 한눈에" 표 + 핵심 1~2줄을 보여주고,
   "자세히는 가이드 문서 참조" 안내.
3. 인자 있으면: 해당 키워드(설정·plan·승인·이벤트 훅 등) 섹션을 찾아 발췌 설명.
4. 사용자가 처음이면 "`/triage-init` 먼저, 그다음 `/work`" 를 강조.

## 핵심 요약 (가이드 못 읽어도 이것만은)
```
/triage-init   ← 새 프로젝트 1회 (설정 생성)
/work <할 일>   ← 평소. 버그/기능 알아서 분류
"ㅇㅋ"          ← 이슈·설계 승인하면 PR까지 자동
/triage-status ← 현황 조회
```
전체 가이드: `${CLAUDE_PLUGIN_ROOT}/docs/triage-workflow-guide.md`
