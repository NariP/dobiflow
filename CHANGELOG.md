# Changelog

이 프로젝트의 주요 변경사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르며,
[유의적 버전](https://semver.org/lang/ko/)을 사용합니다.

## [0.8.1] - 2026-07-05

### Added
- `install.sh --link` — 복사 대신 심링크 설치. 클론에서 git pull/파일 수정만으로 즉시 반영(재설치 불필요).
  기본은 복사 유지. 복사 모드는 기존 심링크 설치물을 먼저 제거 후 복사(원본 덮어쓰기 방지) — 모드 전환 양방향 안전

## [0.8.0] - 2026-07-05

### Added
- **구현 루프** — 승인 후 5단계가 "메인 세션 직접 구현"에서 "루프 컨트롤러"로 바뀜.
  매 반복: `implementer` 에이전트(신규, 쓰기 가능) 구현+lint·테스트 → policy-checker+code-reviewer 병렬 →
  판정(APPROVE / REQUEST_CHANGES / 막힘). ❌ 지적이 나오면 지적사항을 들고 자동 재구현,
  최대 `loop.max_iterations`회(기본 3, config 오버라이드). 소진·막힘 시 커밋·PR 없이 중단·보고(WIP 유지) (claude+codex)
- `implementer` 에이전트 — 구현 전담. loop.md 완료 기준·반복 지시 기반 최소 편집, 실패 상태로 완료 보고 금지,
  커밋/push/이슈/PR 금지(메인 세션 몫) (claude `agents/implementer.md` + codex `agents/implementer.toml`)
- loop.md — `.claude/loops/<이슈번호>/loop.md` 일회용 작업 파일(완료 기준·검증 명령·반복 로그).
  `.git/info/exclude`로 추적 제외, PR 후 삭제. 갱신은 메인 세션만
- `triage.config.json`에 `loop.max_iterations` 필드 (triage-init 스키마 반영)

### Changed
- triage-fix/task-run 5단계·5.5단계 → "5단계 구현 루프"로 통합. 커밋·push는 APPROVE 후 1회로 제한
- 가드 추가: 메인 세션 직접 구현 금지, 루프 안 커밋·push 금지
- install.sh 에이전트 4개 설치, 워크플로우 가이드·README 흐름도 갱신

## [0.7.1] - 2026-06-22

### Fixed
- "수정해줘/고쳐줘" 같은 직접 명령이 입력에 섞여 있을 때 이슈 생성·승인 절차를 건너뛰던 문제 방지 — work/triage-fix/task-run 가드에 "직접 명령 ≠ 절차 생략" 명시 (claude+codex)

## [0.7.0] - 2026-06-19

### Added
- **이벤트 훅** — dobiflow가 GitHub 이슈/PR 생성 시 사용자 정의 스크립트 자동 실행. `hooks/hooks.json`(PostToolUse) + `scripts/dobiflow-hook.sh`(디스패처). 사용자 훅 위치: 전역 `~/.dobiflow/hooks/on-{issue,pr}-created.sh` + 프로젝트 `.claude/dobiflow-hooks/`. 환경변수 `DOBIFLOW_{EVENT,URL,COMMAND,CWD}` 전달. 예시 `hooks/examples/`. 훅 실패는 본 작업 비차단.

## [0.6.0] - 2026-06-19

### Changed
- `/work`를 **읽기 전용으로 강제** — frontmatter `disallowed-tools: Edit, Write, NotebookEdit`로 work 실행 중 코드 수정을 실제 차단(소프트 가드 아님). work는 분류·분해·배치만, 실제 수정은 승인 후 task-run/triage-fix가 담당. work 도중 멋대로 코드를 고치던 문제 방지 (claude+codex)

## [0.5.0] - 2026-06-19

### Added
- `/work`에 **작업 분해 단계** — 한 노션/이슈에 코드 작업이 여러 개면 먼저 쪼개서 보여주고 "각각 따로 이슈·PR vs 하나로 묶기 vs 상위+하위"를 사용자가 선택
- `/work`를 **PM 역할**로 명시 (직접 구현 X, 파악→분해→배치→진행관리)

## [0.4.1] - 2026-06-19

### Fixed
- task-run 4단계 승인 정지점 강화: 범위/접근 질문 답을 "설계 승인"으로 착각해 구현으로 직행하던 문제 방지 — 4단계 "이대로 구현할까요?"에 명시적 OK를 별도로 받도록 가드 추가 (claude+codex)

## [0.4.0] - 2026-06-19

### Added
- 이슈·PR 본문 끝에 `🤖 자동 생성됨` 풋터 추가 (봇 생성물 명시)
- `CHANGELOG.md` 도입 — 이후 변경은 여기에 기록

## [0.3.0] - 2026-06-19

### Changed
- 플러그인/레포/마켓플레이스명: `triage-flow` → **`dobiflow`**
- 일반 작업 스킬: `task-fix` → **`task-run`** (수정 뉘앙스 제거, "실행" 의미 명확화)
- `/work` 분류 로직: 제목·키워드 단정 대신 **요구사항 전체를 종합 판단** (구현 항목 있으면 기능 작업, 혼합이면 분리)

> 명령어 `/triage-fix`·`/triage-init`·`/triage-status`·`/triage-help`는 유지 (버그 분류=triage 의미 일치)

## [0.2.0] - 2026-06-18

### Added
- **Codex CLI 지원** — `codex/skills`(6개), `codex/agents`(3개 TOML), `install.sh`(claude/codex 자동 감지 설치)
- README 영문(메인) + 한글(`README.ko.md`) 분리
- "동작 조건과 한계" 섹션 (로컬 클론 필요·코드작업 한정·계정 게이트 등)

## [0.1.0] - 2026-06-18

### Added
- 첫 공개. Claude Code 플러그인으로 패키징
- 스킬 6개: `/work`(라우터) · `/triage-fix`(버그) · `/task-run`(기능) · `/triage-status` · `/triage-init` · `/triage-help`
- 에이전트 3개(읽기 전용): `issue-triage` · `policy-checker` · `code-reviewer`
- 멀티레포 라우팅, 멀티계정(GH_TOKEN 주입 + 오발송 게이트), 프로젝트별 설정 자동 생성
- 이슈→파악→승인→수정→자가체크→PR 워크플로우 (전부 로컬 실행)
