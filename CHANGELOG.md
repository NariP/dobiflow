# Changelog

이 프로젝트의 주요 변경사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르며,
[유의적 버전](https://semver.org/lang/ko/)을 사용합니다.

## [0.13.0] - 2026-07-10

### Added
- **마일스톤 — 큰 업무를 개발팀처럼 나눠 실행** (claude+codex):
  - `/milestone` 스킬 신설 — 큰 업무를 작은 태스크로 쪼개고, 관련끼리 **그룹**(=개발자 1명)으로 묶어
    **그룹은 병렬·그룹 내는 순차**로 실행. 흐름 ①파악·분할 → ②파일계획 → ③그룹핑 → ④순서 →
    ⑤승인(계획+실행모드 단일 정지점) → ⑥이슈·Milestone → ⑦브랜치·worktree →
    ⑧그룹 실행(정식 loop.md 재사용) → ⑨그룹 PR 머지 전 검증(merge-queue식) → ⑩최종 main PR(사람 머지).
  - `planner` 에이전트 신설 — 태스크 분할·파일계획·완료기준(테스트로)·그룹핑(ownership matrix로 겹침 검사)·
    순서까지 계획만 담당하는 읽기 전용. evidence packet 소비.
  - `qa` 에이전트 신설 — 완료기준 테스트 감사 + 테스트·full_verify **실행·통과 판정**. 자가체크 3번째 축.
  - **브랜치 3계층** `main → milestone/<슬러그> → group/<슬러그>-<그룹>` (태스크별 브랜치 없음).
  - **막힘·통합 깨짐 = 새 이슈**(중복 마커), 성공한 태스크만 커밋. main 머지는 항상 사람 관문.

### Changed
- **`git-writer` 확장** — 기존 "이슈 생성 / 커밋+PR"에 마일스톤 op 추가(claude+codex):
  `create-branch`·`add-worktree`·`remove-worktree`·`create-milestone`·`prepare-merge`(임시 검증 worktree에서 커밋 M 생성·SHA 반환)·
  `merge`(검증한 SHA 그대로 ff-only + 검증 worktree 정리)·`close-issue`·`cleanup-branch`. "브랜치 생성 금지" 가드는 **마일스톤 op 한정** 해제. 실패 시 구조화 반환.
- **자가체크 2축 → 3축(qa 추가)** — triage-fix·task-run 구현 루프와 PR 셀프체크에 qa(테스트 실행·판정) 편입.
  완료기준을 **테스트로** 쓰고(implementer 작성), 테스트 실행 책임을 implementer → **qa로 이관**(claude+codex).
- **loop base 브랜치 파라미터화** — 단일 흐름은 기존대로 default_branch, 마일스톤은 그룹 브랜치 주입(claude+codex).
- **`triage-init` config 확장** — `milestone`(base_branch·max_issues·max_parallel)·`models`(진영별 모델 매핑)·
  `branch_prefix`(milestone/group) 블록 신설. 스킬→서브에이전트 model 오버라이드 배선(claude+codex).
- **`work` 라우팅에 규모 축 추가** — 종류(버그/기능)와 별개로 작다/크다 판단, "크다"면 확인 후 `/milestone`
  라우팅. 작업 분해 시 ⓐ마일스톤/ⓑ각각/ⓒ하나로 선택 제공(claude+codex).
- **`install.sh`** — SKILLS에 `milestone`, AGENTS_MD에 `planner qa` 추가. 설치 로그 "스킬 7개 + 에이전트 7개".

### 설계 리뷰 반영 (토큰·정합성)
- **커밋 M 생성 위치 명시** — 머지 전 검증할 "합친 커밋 M"을 **임시 검증 worktree**에서 만들도록 명확화
  (git-writer `op=prepare-merge`). 메인 레포·그룹 worktree를 안 건드리고, 검증한 SHA를 그대로 ff-only 머지(claude+codex).
- **full_verify 실행은 하위 모델로** — qa의 두 역할 중 ⑨⑩ 실행·판정은 감사가 아니므로 하위 모델 스폰 허용(토큰 절약).
- **worktree 의존성 준비 단계** — 새 worktree는 node_modules가 없어 테스트가 안 도니 `install_command`(config 신규) 실행.
- **verify.log 크기 규율** — 실패 로그 전문 대신 **구조화 요약**(pass/fail·실패명·tail)만, 원문은 경로만(검증자 컨텍스트 폭발 방지).
- **재진입 절차** — 컴팩션·세션 사망 후 plan.md → 태스크 산출물 → git/gh 상태로 위치 재구성, 커밋된 성공 태스크는 재실행 안 함.
- **탐색 캐시 hit 계측** — `cache_hits`/`cache_misses`를 누적해 최종 PR에 히트율 기록(캐시 실효성 데이터화).
- **컨트롤러 실행 규칙 명확화** — "어떤 커맨드도 금지"가 아니라 **git·gh·테스트만 위임**, 상태 파일 읽기·쓰기와 가벼운 조회는 컨트롤러 직접.

### Fixed
- **change-map 배선 완결** — 스펙(§9·§10·§17-7)엔 있으나 구현에서 끊겨 있던 산출물 연결 (claude+codex):
  - `implementer`에 "change-map 생산" 섹션 신설 — 구현 후 파일별 변경 의도·위험·테스트 연결을 `change_map_path`에 1회 작성.
  - `code-reviewer`·`policy-checker`·`qa` 입력에 `change_map_path` 추가 — 먼저 읽고 의심 지점만 원본 확인(3축이 같은 diff를 각자 통독하던 낭비 제거).
  - `triage-fix`·`task-run`이 스폰 시 `change_map_path` 전달, loop.md 템플릿에 change-map.md 경로 명시.
  - 단일 루프에도 적용 — 규모 무관하게 3축 중복 읽기를 막음. 마일스톤 태스크 루프는 스킬 재사용으로 자동 적용.

## [0.12.0] - 2026-07-07

### Added
- **도비 페르소나 도입** — 사용자 대면 진행 보고에 집요정 "도비" 말투 적용 (claude+codex):
  - `docs/dobi-persona.md` 신설(SSOT) — 톤 규칙·단계별 예시(읽음→멈춤→고침→자유)·적용 범위 정의.
  - 지금까지 도비 말투는 README(마케팅 카피)에만 있고 실제 스킬엔 톤 지시가 없어, 실행 시 평범하게
    대답했음. 이 갭을 페르소나 파일 + 스킬 참조로 메움.

### Changed
- **`work`·`triage-fix`·`task-run` 스킬이 페르소나를 참조** — 인라인 복제 없이 참조 한 블록씩 (claude+codex):
  - Claude: `${CLAUDE_PLUGIN_ROOT}/docs/dobi-persona.md` (triage-help가 쓰던 관례와 동일).
  - Codex: 변수 미지원이라 각 스킬 `references/dobi-persona.md` 복제본 참조.
  - **적용 범위** — 사용자 대면 진행 보고·정지점·완료 알림에만 도비 톤. **이슈/PR 본문·loop.md·
    서브에이전트 프롬프트·커밋은 중립 문체**(GitHub·팀·도구가 읽는 기록이라 정확성 우선).
  - 톤은 표현일 뿐 각 스킬의 가드·정지점·승인 절차를 바꾸지 않음.

### Fixed
- **`install.sh` 공용 문서 배포 누락 보강** — Claude 수동 설치 시 `docs/*.md`를 `~/.claude/docs/`로
  복사하도록 추가. 스킬이 `${CLAUDE_PLUGIN_ROOT}/docs/*.md`로 참조하는 문서(dobi-persona,
  triage-workflow-guide)가 install.sh 경로에서도 풀리도록 함.

## [0.11.2] - 2026-07-06

### Fixed
- **문서 정합성 뒷정리** — 최근 큰 변경(멀티계정 제거·git-writer 신설) 이후 남은 불일치 정리 (claude+codex):
  - `install.sh` 설치 로그 "에이전트 4개" → "5개"(git-writer 반영. 실제 설치 목록은 이미 5개였음).
  - `triage-workflow-guide.md`(+codex 미러) agents 나열에 `git-writer (쓰기 실행 전담)` 추가.
  - README 배지 버전 `0.10.0` → `0.11.2`(양쪽).
  - `plugin.json`·`marketplace.json` 설명에서 제거된 "멀티계정" 문구 삭제, marketplace 흐름도를 "구현 루프"로 정합화.
  - `task-run` 0단계의 폐지된 `.local.json` 읽기 잔재 제거(+codex 미러).

### Changed
- **loop.md 핸드오프 누수 개선** — implementer 재탐색으로 인한 토큰 낭비 감소 (claude+codex):
  - loop.md "관련 위치"를 이슈 본문(사용자용 요약, 파일:줄이 깎임) 대신 **2단계 issue-triage 반환 원본에서
    직접 복사**하도록 변경. 메인이 이미 갖고 있는 값이라 추가 토큰 0. 핸드오프가 상세할수록 implementer가
    코드베이스를 재탐색할 필요가 줄어 메인↔서브 왕복 낭비가 감소한다. (triage-fix·task-run 4개 파일)

## [0.11.1] - 2026-07-06

### Changed
- **메인↔서브에이전트 토큰 낭비 개선** (#1) — issue-triage로 워크플로우를 감사해 찾은
  낭비 지점을 정리 (claude+codex):
  - **자가체크 diff 전달 단일화** — "변경 파일 목록 또는 `git diff` 전달"에서 OR을 없애고
    **변경 파일 경로 목록만** 전달. `git diff` 전문을 프롬프트에 넣지 않는다(메인이 diff를
    자기 컨텍스트에 올려 policy-checker·code-reviewer 프롬프트로 복제하던 3벌 낭비 제거).
    diff가 필요하면 checker가 자기 Read로 해당 파일을 연다. 델타 재검증 개념은 유지.
  - **implementer 보고에 "변경 파일" 필드 추가** — 메인이 diff를 스스로 뜨지 않고 이 목록만 넘긴다.
  - **convention_doc 부분 읽기 확산** — code-reviewer·implementer도 문서 전체가 아니라
    변경 관련 섹션만 Read(기존 policy-checker 패턴을 확산).
  - **자가체크 통과 시 규칙 나열 금지** — 통과 항목을 나열하지 않고 "위반 없음" 한 줄로 끝낸다.
  - checker 입력 설명도 "경로만 받는다(diff 전문 없음)"로 정합화. 미러(codex) 대칭 유지.
  - 안 건드림: git-writer 전체, 델타 재검증 개념, porcelain 예외.

## [0.11.0] - 2026-07-06

### Added
- **`git-writer` 서브에이전트 — 쓰기 실행 위임(멍청한 손)** — 이슈 생성·커밋·push·PR 생성의
  *실행*을 전담하는 에이전트. 목적은 **컨텍스트 절약** (claude+codex):
  - **역할 경계**: 메인 세션이 판단·작성(커밋 메시지·PR 본문·리뷰어·라벨·스테이징)을 다 끝내고,
    git-writer는 완성값을 받아 `gh`/`git`에 넣어 실행만 한다. **URL만 반환**.
  - **읽지 않음**: git-writer는 `git log`/`diff`/`status`/코드를 읽어 무언가 추론하지 않는다 —
    필요한 값은 메인이 전부 넘겼으므로. 장황한 gh/git 출력이 메인 세션에 안 쌓인다.
  - triage-fix(3·6단계)·task-run(4·6단계)이 이슈/PR 시점에 git-writer로 위임하도록 갱신.
  - `agents/git-writer.md`(Claude) + `codex/agents/git-writer.toml`(Codex) 신설, install.sh 설치 목록 추가.
  - architecture.md에 side-effect boundary(판단은 메인 독점, 실행은 손에 위임, 읽기는 안 함) 반영.

### Changed
- **멀티계정 지원 제거 — 현재 gh 로그인·git 설정을 그대로 신뢰** — 계정 전환은 `gitto` 같은
  도구가 git 레벨에서 처리하므로 dobiflow에서 멀티계정 로직 전부 제거 (claude+codex):
  - `GH_TOKEN` 추출·`x-access-token` URL push 주입·`WHO` 오발송 게이트·멀티계정 시퀀스 섹션 삭제.
  - config에서 `account`·`git_identity` 키 제거, `triage.config.local.json` 폐지(단일 config로).
  - 커밋 author 주입 제거 → 현재 git 설정 그대로. `gh`/`git`을 인증 주입 없이 평범하게 실행.
  - triage-init: account/git_identity 감지·질문 제거, 구버전 `.local.json` 정리 안내 추가.
  - README(양쪽)·워크플로우 가이드·architecture.md에서 멀티계정 서술 정리.

## [0.10.0] - 2026-07-05

### Added
- **작업 생명주기 이벤트** — 구현 루프의 시작/진행/종료를 사용자 훅으로 발행. 여러 세션·레포에서
  도는 작업을 외부 서비스로 모으는 용도 (`work-started` 등록 → `work-finished`/`work-stopped` 해제) (claude+codex):
  - 신규 이벤트 4개: `work-started`(루프 진입) / `iteration-completed`(매 반복 판정) /
    `work-finished`(PR 생성) / `work-stopped`(막힘·max 소진 중단)
  - `scripts/dobiflow-emit.sh` 발행기 신설 — install.sh가 `~/.dobiflow/bin/dobiflow-emit`으로 설치.
    `key=value` 인자를 `DOBIFLOW_<KEY>` 환경변수로 변환해 사용자 훅에 전달, 실패 비차단(항상 exit 0).
    미설치면 스킬이 조용히 생략 (`test -x` 1회 확인)
  - 사용자 훅 위치는 기존 이벤트 훅과 동일: `~/.dobiflow/hooks/on-<event>.sh`(전역) +
    `<repo>/.claude/dobiflow-hooks/on-<event>.sh`(프로젝트)
  - 예시 `hooks/examples/on-work-started.sh.example` (JSONL 장부 적재 + 외부 전송)
  - triage-fix/task-run 5·6단계에 발행 시점 명시 + "이벤트 발행" 섹션. README 이벤트 표 추가
  - 워크플로우 가이드에 반영: 특징 항목 + FAQ("여러 세션 작업 한곳에 모으기") + 구성 트리(hooks/·scripts/·프로젝트 dobiflow-hooks/). triage-init 4단계 보고에 훅 위치 한 줄 안내

## [0.9.0] - 2026-07-05

### Changed
- **구현 루프 속도 개선** — 실측(1파일 수정에 17분·서브에이전트 7회) 기반 4건 (claude+codex):
  - **핸드오프 강화** — loop.md에 "관련 위치" 섹션 신설. issue-triage가 찾은 파일:줄·흐름을
    이슈에서 복사해 두고, implementer는 코드베이스 재탐색 전에 여기부터 본다
  - **델타 재검증** — 자가체크 2회차부터는 풀 리체크 대신 "직전 지적사항 + 이번 회차 변경 파일
    diff"만 검증 (지적 해소 여부 + 델타의 새 위반). policy-checker·code-reviewer에 재검증 모드 입력 추가
  - **무거운 검증 분리** — `loop.full_verify_command`(신규 config, triage-init이 build 스크립트
    감지·제안). 루프 안 반복 검증은 lint·테스트만, 풀 빌드는 APPROVE 시점 1회
    (실패 시 REQUEST_CHANGES로 루프 복귀). implementer는 지시 없이 무거운 검증을 돌리지 않음
  - **심각도 분류 보강** — 동작 회귀·데이터 손실·보안 노출 가능성은 확신이 낮아도 ⚠️가 아닌
    ❌로 분류(policy-checker·code-reviewer). 메인 세션의 ⚠️→❌ 승격 재량도 명문화(사유 loop.md 기록)

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
