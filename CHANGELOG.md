# Changelog

이 프로젝트의 주요 변경사항을 기록합니다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르며,
[유의적 버전](https://semver.org/lang/ko/)을 사용합니다.

## [1.3.0] - 2026-09-03

머지 후 정리에 비용·시간 리포트 — 작업에 시간·토큰·돈이 얼마나 들었는지 보여준다.

### Added
- **머지 후 정리에 비용·시간 리포트(#62)** (claude+codex) — 정리 단계(triage-fix·task-run 7단계, milestone ⑩) 끝에
  ✋ 한 번 물어보고, 원하면 활성 작업시간 + 메인/서브에이전트 종류별 토큰·비용을 표로 출력.
  집계는 `scripts/dobiflow-cost.sh` 한 곳에 모여 있고 스킬은 호출만 한다(로직 중복 없음).
  로컬 세션 기록만 읽고 외부 전송 없음. 스크립트가 없거나 실패해도 정리를 막지 않는다(항상 exit 0).
  캐시 read/write(5m·1h)를 각각의 배수로, 모델별 단가로 계산하며 `[1m]` 접미사는 할증 없이 기본 단가로 처리.
  소요시간은 벽시계 span이 아니라 **간격 5분 이하만 합산한 활성 작업시간**(실측: 벽시계 93시간짜리 세션의
  실제 작업은 47분). 기본은 3열 표, "자세히" 요청 시 캐시 내역·절약액까지 확장. 출력 문구는 사용자 언어에 맞춰 분기.
  `install.sh`가 `~/.dobiflow/bin/dobiflow-cost`를 설치하므로 **기존 사용자는 install.sh 재실행 필요**.

## [1.2.1] - 2026-09-01

문서 패치 — main(디폴트 브랜치)의 README가 v1.2.0 동작과 업데이트 절차를 설명하도록.

### Changed
- **README 업데이트 안내 통합 + v1.2.0 문서 동기화(#60)** — 설치 섹션 끝에 Updating/업데이트 섹션 신설(Claude 마켓플레이스 / Codex `git pull` + 에이전트 변경 시 `install.sh --codex-only` / `--link`), Codex 블록의 인라인 Updating 문단은 이동. 자가체크 불릿을 2단계(Phase A 실행 ∥ / Phase B 감사)로 갱신, 테스트 레벨(`Test(unit):`/`Test(e2e):`/`Covered-by:`, `e2e_command`·`test_policy`) 불릿 신설, How Dobby works 다이어그램에 게이트 줄(APPROVE 시 full_verify+e2e 1회 · 부채 테스트 감사) 추가, 업데이트 알림 불릿의 "Codex: 자동 반영"을 실제 안내 문구와 일치, EN `--link` 경고 보강(영·한 대칭). docs/architecture.md 부작용 경계에 서브에이전트 총 8개 명시. 스킬·에이전트 변경 없음(Codex 에이전트 재설치 불필요)

## [1.2.0] - 2026-09-01

완료기준 테스트 레벨 분리 — e2e를 자가체크에서 떼어 머지 게이트로.

### Added
- **테스트 레벨 분리 — `e2e_command`·`test_policy` 설정 신설(#56)** (claude+codex) — e2e만 있는 실사용 프로젝트에서 셸스크립트 검증까지 e2e spec으로 작성되고 라운드마다 전량 재실행돼 자가체크가 라운드당 15~22분 걸리던 병목 해소. `test_command`는 unit/integration 러너만(감지 시 playwright/cypress 실행 스크립트 제외), `e2e_command`(선택)는 머지 게이트(단일 태스크 APPROVE·마일스톤 ⑨⑩·Track-C)에서만 `full_verify_command`와 같은 자리에서 1회 실행. `test_policy`(enum: `ui-flow-only` 기본 / `merge-gate-only` / `unrestricted`)는 e2e "신규 작성" 범위만 지배 — 실행 시점은 정책과 무관하게 고정. triage-init이 e2e-only 프로젝트를 감지하면 경고("자가체크 라운드에 테스트 실행 없음 — unit 러너 추가 권장") + `test_policy` 1문항, triage-status 설정 요약에 세 키 표시. 완료기준 어휘 `Test(unit):`/`Test(e2e):`/`Covered-by:` 신설(무태그 `Test:`=unit 하위호환, `Test(e2e):`는 정책 근거 한 줄 필수) — planner가 태그 제안, implementer는 e2e 직접 실행 금지, qa는 정책 위반 e2e를 `fail`(사유 `policy`)로 감사. `test_command` 미설정 시 러너는 `runner skipped (no test_command)` — 빨강 아님, 감사는 "실행 증거 없음"으로 진행
- **README 기여 섹션(#58)** — PR은 `develop`로, `main`은 stable(릴리스 때만 이동), 릴리스는 develop bump → develop→main PR → 태그(`release/*` 브랜치 없음). 영·한 대칭

### Changed
- GitHub 디폴트 브랜치 `develop` → `main` — 방문자·`/plugin marketplace add`·`git clone`이 항상 마지막 릴리스를 받도록 (레포 설정 변경, 2026-08-31)

## [1.1.0] - 2026-07-30

구현 루프 비용 절감(qa 실행/감사 분리) + PR 본문의 QA 대본화.

### Added
- **qa 실행/감사 분리 — `qa-runner` 에이전트 신설(#47)** (claude+codex) — 테스트 실행·verify.log 작성은 qa-runner(기본 haiku), 적정성 감사·verdict는 qa(opus 유지, tools에서 Bash 제거로 "감사는 테스트를 못 돌림"을 구조로 강제). 자가체크 배선은 phase A(qa-runner ∥ code-reviewer ∥ policy-checker 병렬) → phase B(러너 초록일 때만 qa 감사, 빨강이면 감사 스킵을 loop.md에 "audit skipped (red)"로 기록 — fail-fast). milestone ⑨⑩의 "감사 없는 호출은 하위 모델 대체" 임시방편은 qa-runner 정식 호출로 대체. 하위 모델 적합성은 5개 함정 시나리오(스냅샷 `-u`·`--passWithNoTests`·대량 실패 로그·lint 차단·환경 에러) 재평가 3라운드로 검증 — 상태값 3개 강제·실패명 전수 나열+개수 대조·에러 줄 verbatim 인용·되묻기 금지를 명문화. `models.qa-runner` 미지정 시 inherit — 기존 config 하위호환
- **PR 본문 QA 시나리오 섹션(#48)** (claude+codex) — change-map에 `user-facing` 필드 신설(파일별 yes/no — 화면·플로우·인터랙션·CLI 출력·에러 메시지·API 응답 등 지각 표면). yes가 하나라도 있는 PR에만 유저 플로우 시나리오(준비·순서·확인 지점 3종: 보여야 하는 것/보이면 안 되는 것/회귀·수정 전 동작)를 생성 — 사람·AI 브라우저 QA가 그대로 따라 실행할 수 있는 대본. 전부 no면 섹션 자체 생략("해당 없음" 금지). 정의는 triage-fix §PR template 한 곳(SSOT), 마일스톤은 ⑩ 최종 PR에서 전체 change-map 종합
- **triage-status 설정 요약(#49)** (claude+codex) — 출력에 역할별 모델 매핑(미지정 `inherit`)·주요 설정(`repo`·`default_branch`·`loop.*`·`worktree`·`serena`·`milestone.base_branch`)·읽은 config 경로 표시. config 부재 시 깨지지 않고 "`/triage-init` 권장" 안내만 (읽기 전용 가드 유지)

### Changed
- install.sh — 에이전트 8개(qa-runner 추가), usage() 목록의 planner·qa 누락 정정
- docs/architecture.md — 자가체크 상호 맹목 원칙에 "러너→감사는 판정이 아닌 사실만 흐르는 유일한 의도적 예외" 서술 추가
- docs/dobi-persona.md — 말투 미적용 목록에 QA scenario 섹션 추가 (Codex 복제본 3개 동기화)

## [1.0.0] - 2026-07-26

글로벌 준비 완료 — 실행 로직 영어화 + 사용자 언어 자동 대응으로 첫 메이저 릴리스.

### Added
- **i18n — 도비 말투·이슈/PR/loop.md 템플릿의 사용자 언어 자동 대응(#40)** — dobiflow가 LLM 에이전트라
  입력 언어를 자연히 아는 특성을 활용(접근 A). config·감지 코드 없이 지시를 언어중립화 —
  한국어로 입력하면 한국어 산출물, 영어면 영어. 원칙: 실행 로직(절차·가드)=영어 고정 / 사용자 대면=사용자 언어.
  한글 템플릿 스켈레톤을 언어중립 지시로 바꿔 토큰도 감소. (claude+codex)

### Changed
- **실행 문서 영어화 — 스킬·에이전트·persona·workflow-guide(#26~#35)** — 매 실행 컨텍스트로 로드되는
  실행 로직(절차·가드·명령·인용대사)을 영어화해 LLM 토큰 절감(근사 40%). 7개 스킬 SKILL.md, 7개 에이전트
  (claude .md + codex .toml), persona SSOT + 복제본 3벌(도비→Dobby, README 관례 일치), workflow-guide 2벌.
  frontmatter description·README·생성물 규칙은 한국어 유지. 가드 인벤토리 전량 보존(11·10·6·7·3·3·0),
  미러 divergence 보존, Codex sol/xhigh 게이트·Claude 내부 대조로 검증. (claude+codex)
- **토큰 다이어트 — 반복 산문 압축(#42-B)** — Serena 멱등성 정당화 중복·git-writer 위임 섹션(agents SSOT 중복)·
  "qa's job" 3회 반복·승인 예시 verbatim을 압축(-78줄). 가드·의미 0 손실, Codex 교차검증 VERDICT SAFE. (claude+codex)

### Fixed
- **Codex 에이전트 role toml의 malformed mcp_servers(#36)** — `mcp_servers = ["serena"]`(배열)이 Codex 0.145.0에서
  'invalid type: sequence, expected a map'으로 role 7개를 통째로 무시하던 문제. OpenAI 공식 config-reference 근거로
  배열 줄 제거(MCP는 config.toml에 정의하는 게 정석). (codex)
- **i18n fallout — 깨진 섹션 참조·triage-status 한글·용어 드리프트(#42-A)** — 영어화·i18n이 템플릿 헤딩을
  언어중립화하며 생긴 참조 불일치 5건(이모지 섹션명·triage-status 출력 한글 누락·Related/relevant 드리프트·
  config 열거 누락). 감사 + Codex 교차리뷰로 확인·수정. (claude+codex)
- **work 스킬 Dobi→Dobby 표기 통일(#26 리뷰)** — 영어화 시 work만 "Dobi"로 번역돼 persona SSOT·타 스킬과
  불일치하던 것 통일. improve→improvement. (claude+codex)

## [0.20.0] - 2026-07-24

### Changed
- **스킬 문서 다이어트 — 호출당 토큰 비용 절감(#22)** — 의미·실행 가드를 잃지 않고 표현 중복만 로컬 압축하고,
  판단 없는 서브에이전트의 저가 모델 권장을 문서화. Codex 계획 검토 2라운드(PROCEED-WITH-CHANGES) 반영 —
  "참조로 중복 제거"는 가드 소실 위험으로 폐기하고 **같은 파일 안에서 표현만 축약**(실행 시 전부 로드).
  - **A. 로컬 압축** — `/work` 도식·분류 원칙·분류 기준·동작 산문, triage-fix/task-run의 5.5단계 부채 감사
    요약(fast-path 2개·판별·범위·절차 전부 유지), loop.md 템플릿을 필드 스키마형으로 축약 (claude+codex 미러).
  - **B. agents 첫 문단 축약** — 7개 에이전트(claude .md + codex .toml)의 본문 첫 문단 역할 소개가 frontmatter
    description과 중복되던 것만 제거. **frontmatter description은 보존**(스폰 라우팅 계약), git-writer op 계약·명령·금지 조항은 제외.
  - **C. 다운시프트 문서화** — triage-init `models` config에 "판단 없는 손(git-writer)=하위 모델 / qa는 판정자라
    강모델 유지" 근거와 "git-writer Haiku 추가 하향은 op 시나리오 평가 통과 시에만" 조건 명시 (claude+codex 미러).
    코드 변경 없이 문서·권장까지(실제 저가 모델 실행 평가는 별도 후속).
  - **가드 무손실 검증** — 압축 전 가드 인벤토리(실행 가드·정지점·명령·제어흐름 분기) 목록화 후 압축본 전량 잔존 대조 +
    시나리오 6개(미머지 PR·dirty worktree·열린 milestone 이슈·병렬 Serena·활성화 실패·테스트 제거 후 red) 처리 확인.
  - **관측 줄 수(목표 아닌 관측치)** — skills(claude): work 114→91·triage-fix 377→369·task-run 239→236·
    milestone 188(불변)·triage-init 111→112(C 근거 추가) = 합계 1029→996(−33). skills(codex): 1021→987(−34).
    agents: 첫 문단 중복 제거로 파일당 1~2줄·반복 문구 축소(claude 571→570, codex 434). 절감 핵심은 표면 줄 수보다
    **호출·스폰당 반복 로드되는 중복 문구 제거**(SKILL=슬래시 호출마다 로드, agents=스폰마다 로드).

## [0.19.1] - 2026-07-23

### Fixed
- **v0.15~0.19 교차 정합성 수리 13건** — 종합 감사(모순·성능 2렌즈)에서 발견된 실질 결함 3·공백 5·저비용 개선 5를 일괄 수리:
  - **worktree 분기 마일스톤 제외 가드** — triage-fix·task-run 5단계 worktree 준비에 "마일스톤 모드 건너뜀" 가드 추가.
    그룹 브랜치와 `op=add-worktree` 충돌·실패 폴백의 그룹 격리 파괴 방지 (claude+codex).
  - **7단계 sweep 안전선·순서** — remove-worktree 대상을 닫힌 이슈·머지된 브랜치의 worktree로 한정(병행 작업 오삭제 방지),
    순서를 worktree 제거→브랜치 삭제로 교정(체크아웃 브랜치 `-d` 거부), 6단계에 worktree 정리 안내 1줄 (claude+codex).
  - **"머지했어" 트리거 판별** — 7단계 1에 마일스톤 판별 규칙(`plan.md` 폴더는 sweep 제외, `/milestone` ⑩ 라우팅) +
    milestone ⑩ 상호참조 — Milestone close 확인 ✋ 우회 방지 (claude+codex).
  - **적층 retarget 경고** — milestone 적층 ⑤·⑩ + 가이드 구조도: C 머지 전 A 원격 브랜치 삭제 선행
    (retarget은 base 삭제 시에만 발동 — 실제 발생 사례) (claude+codex).
  - **milestone ⑩ 태깅 편입** — 버전 bump 포함이면 머지 커밋 태그·push(git-writer `op=tag` 신설 — agents 2벌), 적층 연속 머지는 순서대로 (claude+codex).
  - **부채 감사 시점 보강** — 태스크 추가 재진입의 최종 PR 갱신 전 감사·full_verify 재확인, 적층 체리픽된 B 테스트도
    C ⑩ 감사 범위 포함 (claude+codex).
  - **순차 무worktree Serena 경로** — milestone ⑦ worktree 없이 순차 처리 시 activate 대상 = 메인 레포 명시 (claude+codex).
  - **알림 문구 Codex 정정** — `scripts/dobiflow-update-check.sh`: "Codex: 자동 반영" → "Codex: 클론 git pull(에이전트 변경 시 install.sh --codex-only)".
  - **Serena 확인 시점 열거형 폐쇄** — triage-fix·task-run: "탐색 단계 진입 시마다(~등)" → 0단계·2단계 위임 직전
    두 시점(worktree 모드면 5단계 worktree 준비 성공 직후 포함 세 시점)으로 한정, 루프 내 반복 확인 아님 (claude+codex).
  - **5.5단계 fast-path** — 이번 루프 추가 테스트 0건이면 분류 없이 6단계로 (claude+codex).
  - **훅 timeout 5→8초** — `hooks/hooks.json` SessionStart: 최악 경로(ls-remote 저속+curl 3s)의 5초 초과로 캐시 미기록 반복 방지.
  - **worktree Serena 전제 보완** — 안전 전제는 한 세션 내 명시 + worktree activate 후 메인 레포 복귀는 기존 멱등 확인 담당 (claude+codex).
  - **work→milestone 라우팅 방식 명시** — work 라우팅 3곳(0단계 ⓐ·ⓒ, §규모 축, 동작 2ⓐ): milestone SKILL.md를 Read로
    열어 직접 수행(Skill 툴 호출 금지 — 근거는 claude=`disable-model-invocation`으로 거부됨, codex=사용자 명시 호출
    전용 관례) (claude+codex).

## [0.19.0] - 2026-07-23

### Added
- **업데이트 알림 — SessionStart 훅** (claude+codex):
  - `scripts/dobiflow-update-check.sh` 신설 — 세션 시작 시 하루 1회(86400초, `~/.dobiflow/update-check` 캐시)
    원격 최신 태그(`git ls-remote`)와 로컬 플러그인 버전을 비교해 신버전이면 갱신 방법
    (Claude: /plugin 마켓플레이스 / Codex: 자동 반영)·CHANGELOG 링크·새 기능 헤드라인(원격 CHANGELOG
    curl, 실패 무해)을 stdout으로 안내. 캐시 기간에는 재조회 없이 마지막 결과만 재출력.
  - 모든 실패(네트워크 불통·파싱)는 조용히 exit 0, stderr 금지 — 세션 시작을 막지 않음.
    macOS(bash 3.2)·Linux 호환: `timeout` 명령·jq 비의존, 저속 가드는 `http.lowSpeedLimit/Time`·`curl --max-time`.
  - `hooks/hooks.json`에 SessionStart 등록(timeout 5) — 기존 PostToolUse 훅과 공존.
  - **Codex 지원 확인 결과: 등록** — Codex CLI 0.144 바이너리 스키마에서 매니페스트 `hooks` 필드(설정 파일 경로)·
    `SessionStart` 이벤트·`${CLAUDE_PLUGIN_ROOT}` 치환 지원을 확인, `.codex-plugin/plugin.json`에
    `hooks: ./hooks/hooks.json` 등록 — 양쪽 CLI에서 같은 훅이 동작.

## [0.18.0] - 2026-07-23

### Added
- **단일 작업 worktree 옵션 — config `worktree`(기본 `false`)** — `true`면 `triage-fix`·`task-run` 단일 작업도
  `<repo>/.claude/worktrees/<이슈번호>` worktree에서 구현해 메인 워킹트리를 점유하지 않는다.
  5단계 준비에 분기 신설: git-writer `op=add-worktree`로 브랜치+worktree 생성 → `{milestone.install_command}`
  있으면 의존성 설치(마일스톤 ⑦ 관례 재사용) → implementer·자가체크 3축에 worktree 절대경로를 cwd로 전달.
  6단계 커밋은 git-writer `work_path` 파라미터(신설)로 worktree 경로에서 add→commit→push, 7단계 sweep에
  단일 작업 worktree 제거(`op=remove-worktree`) 편입. 생성 실패(디스크·권한) 시 현행 방식 폴백+한 줄 알림,
  Serena 활성화 대상 경로는 worktree 절대경로(0단계 절차 그대로 — worktree별 인덱스라 첫 질의 워밍업),
  상태 파일(`.claude/loops/`)은 메인 레포 중앙 유지. **기본 false면 기존 동작 완전 불변.**
  git-writer 2벌에 worktree op 단일 작업 호출·`work_path` 명시, `triage-init` 2벌 생성 표·스키마에 필드 추가,
  가이드·README 특징 1줄(claude+codex).

## [0.17.2] - 2026-07-23

### Fixed
- **서브에이전트 Serena 미사용 — 메인 중앙 활성화 + 모드별 worktree 정책** — 실측(프론트 6레포·25세션·
  서브에이전트 297건)에서 Serena 호출 101건 중 80건(79%)이 "No active project" 에러로 실패하고 grep/Read로
  조용히 후퇴(Read 누적 314만 토큰). 원인은 user 레벨 MCP 등록에 `--project`가 없어 매 세션 활성 프로젝트
  없이 부팅되는데 활성화 주체도 없던 것. 수리:
  - 스킬 3종(`triage-fix`·`task-run`·`milestone`)에 **메인 중앙 활성화** 절차 — `serena=true`면 메인이
    `get_current_config`로 멱등 확인 후 필요 시 `activate_project <레포 절대경로>` 1회, **탐색 단계 진입
    시마다** 재확인(0단계 1회 아님 — 순차 worktree 사용 후 복귀 보장, 실패 시 한 줄 알리고 계속).
    근거인 "Serena 서버=세션당 1개·활성 프로젝트 1칸·서브 전원 공유"를 스킬 서술에 명시(claude+codex).
  - `milestone` ⑧ **워커 모드별 정책** — 병렬(바이패스)=워커 Serena 호출 금지(grep/Glob/Read만 — 활성 1칸
    경합·메인 레포 기준 결과 혼동 방지), 순차(중지)=자기 worktree 절대경로로 activate 후 허용(claude+codex).
  - 워커 4종(implementer·qa·code-reviewer·policy-checker) md tools에 `activate_project`+`get_current_config`
    추가(codex toml은 mcp_servers 통째 부여라 변경 불필요).
  - **무보고 후퇴 금지** — 전 에이전트 6종×2벌의 "실패하면 grep" 폴백 서술에 "보고 첫머리에
    `serena 폴백(사유)` 명시" 의무 추가, 스킬 수신부는 그 표기를 사용자 보고에 전파.
  - `triage-fix` 1.5단계 "cd = Serena 컨텍스트 정렬" 오류 정정(cd는 MCP 서버의 활성 프로젝트를 바꾸지 않음),
    `triage-init` 2벌에 "등록 감지≠활성화" 주석 + `serena project index` 사전 인덱싱 안내 추가.

## [0.17.1] - 2026-07-22

### Fixed
- **`milestone` ⑩ 정상 종료 시 GitHub Milestone close 누락** — 기존 "loops 삭제" 한 줄을 **머지 후 정리**
  3항목으로 확장: loops 삭제 → **GitHub Milestone close**(git-writer `op=close-milestone` 신설 —
  열린 이슈(미완 태스크·통합·막힘)가 남았으면 닫기 전 확인 ✋ ⓐ이관 후 close/ⓑ열어둠, 0건이면 바로 close,
  자동 close 금지) → 브랜치 정리(`op=cleanup-branch`, 머지된 것만). 적층 ⑥의 B 정리도 같은 op를 참조.
  git-writer 2벌에 `op=close-milestone`(입력 `repo`·`milestone_number`, `gh api -X PATCH … state=closed`) 추가(claude+codex).

## [0.17.0] - 2026-07-22

### Added
- **부채 테스트 감사(5.5단계)** — `triage-fix`·`task-run`에 APPROVE 후·커밋 전 단계 신설:
  이번 루프가 추가한 테스트만 **"깨지면 버그인가, 리팩토링인가"** 기준으로 분류해 구현 세부 결합·
  자명(tautological)·중복 테스트는 제거(implementer), 남은 테스트 1회 재실행 green 확인(red면 롤백·유지),
  제거 내역은 PR 셀프체크 "정리된 테스트"에 기록. 기존 테스트는 제거 제안 금지 —
  main에 부채 테스트가 안 들어간다(claude+codex).
- **`milestone` ⑩ 최종 PR 전 일괄 감사** — 태스크 단계에선 감사하지 않고(추가 테스트는 후속 태스크의
  회귀 그물, ⑧에 명시), 최종 full_verify green 후·최종 PR 생성 전에 마일스톤 전체 추가 테스트를 감사 →
  정리 커밋(마일스톤 브랜치, git-writer) → full_verify 재확인 → PR. 정리 내역은 최종 PR 본문에 기록(claude+codex).
- **"머지 후 정리" 7단계(선택)** — `triage-fix`·`task-run`에 신설. PR 머지 후 사용자의
  "머지했어/정리해줘" 발화로만 진입: 사실 확인(fetch로 머지 커밋 실재, 미머지면 중단) →
  태깅(레포 관례 시, git-writer) → 로컬 sweep(머지된 로컬 브랜치 전부 `-d` 삭제·prunable worktree·
  좀비 loops 폴더 — 미머지는 자동 보호). 테스트 감사는 여기서 안 함(5.5단계에서 머지 전 완료)(claude+codex).
- **가이드에 두 절차 요약** — 특징 섹션에 "부채 테스트 감사"·"머지 후 정리" 요약 추가(claude+codex).

### Changed
- **`docs/architecture.md` 현행화** — 자가체크 2축 → 3축(policy-checker·code-reviewer·qa) 교정,
  마일스톤 모드 패턴 섹션 신설(planner 계획 → 그룹 fan-out → 머지 전 검증), 0단계 마일스톤 감지·
  5.5단계 부채 테스트 감사·7단계 머지 후 정리를 다이어그램·표에 반영. README 버전 배지 0.15.0 → 0.17.0.

## [0.16.0] - 2026-07-22

### Added
- **`milestone`에 "마일스톤 적층" 소절** — 미머지 마일스톤 A 위에 후속 마일스톤 C를 시작하는 절차 ①~⑥:
  ①base=A 브랜치로 시작 → ②흡수할 B의 살릴 태스크는 체리픽(태스크당 1커밋, 연속 구간은 범위 체리픽) +
  직후 full_verify 1회(A+B 조합 green 관문) → ③C 최종 PR base는 main이 아니라 A(diff 오염 방지,
  A 머지 시 자동 retarget) → ④A 전진 시 C에 주기적 머지-인(stale 방지) → ⑤수렴은 A→main 먼저 →
  ⑥흡수된 B 정리(Milestone close·이슈 이관·미완 태스크 재등록·브랜치 정리 — 체리픽 SHA 변경으로 끊기는
  완료 추적 장부 정리). base 선택은 ⑤ 승인 정지점에 합류 — 정지점 추가 없음. ⑦·⑩ base 서술에 적층 참조 연결(claude+codex).
- **`work` 0단계 복수 마일스톤 분기** — 진행 중 plan.md가 2개 이상이면 목록 제시 후
  ⓐ이 중 하나에 태스크로 추가/ⓑ별도 작업/ⓒ마일스톤 합치기(→ `/milestone` "마일스톤 적층" 라우팅) 확인.
  단일 감지 시 기존 ⓐ/ⓑ 유지(claude+codex).
- **가이드에 적층 구조도** — 마일스톤 섹션에 ASCII 구조도(번호가 적층 절차 ①~⑥과 대응) + 요약 추가(claude+codex).

## [0.15.0] - 2026-07-22

### Added
- **`work`에 진행 중 마일스톤 감지 단계(0단계)** — 분류 전에 `<repo>/.claude/loops/*/plan.md` 존재로
  진행 중 마일스톤을 감지(plan.md는 마일스톤 전용)하고, plan.md의 이슈 #N 상태를 gh로 교차확인해
  정리 누락된 좀비 폴더를 배제. 감지되면 ⓐ이 마일스톤에 태스크로 추가(`/milestone` 태스크 추가
  재진입으로 라우팅)/ⓑ별도 작업 확인 후 진행. 다이어그램 분기 + "묻지 않고 분류 직행 금지" 가드 추가(claude+codex).
- **`milestone` 재진입에 "태스크 추가" 절차** — 진행 중 마일스톤에 새 수정사항이 들어오면
  위치 재구성 → planner 재계획(태스크 분할·기존/새 그룹 배치·ownership 겹침 재검사·plan.md 갱신, 기존 #N 보존) →
  새 이슈 생성·#N 고정 → 해당 그룹에서 정식 태스크 루프로 실행 후 그룹 PR → 최종 PR 흐름 합류
  (최종 PR이 이미 열려 있으면 갱신)(claude+codex).

## [0.14.0] - 2026-07-20

### Added
- **Codex 스킬 플러그인화** — Codex CLI(0.144+) 플러그인 시스템으로 배포 방식 통일:
  - `.codex-plugin/plugin.json` 신설 — `skills: ./codex/skills/` 지정. 매니페스트 디스커버리 순서가
    `.codex-plugin → .claude-plugin`이라 Claude 플러그인과 한 레포에서 공존.
  - 마켓플레이스는 기존 `.claude-plugin/marketplace.json`을 Codex가 레거시 경로로 그대로 읽음(중복 파일 없음).
  - 설치: `codex plugin marketplace add <클론>` + `codex plugin add dobiflow@dobiflow` —
    스킬 7개가 `dobiflow:` 네임스페이스로 노출(Claude와 동일한 UX).

### Changed
- **`install.sh` Codex 섹션 축소** — 스킬 홈 복사(`~/.agents/skills`·`~/.codex/skills`) 제거,
  구버전 복사본 자동 정리. 서브에이전트(toml)만 계속 복사 — Codex 플러그인 매니페스트가
  skills·mcpServers·apps·hooks만 지원하고 **에이전트 role은 미지원**(config 레이어 `~/.codex/agents/` 전용).
  CLI가 플러그인을 지원하면 마켓플레이스 등록·설치까지 자동 시도.

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
