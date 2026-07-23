---
name: milestone
description: 큰 업무를 여러 태스크로 쪼개 개발팀처럼 병렬 실행하는 워크플로우 — 계획(태스크 분할·파일계획·완료기준·그룹핑) → 승인 → 이슈·Milestone·브랜치·worktree → 그룹 병렬 실행(그룹 내 순차) → 그룹 PR 머지 전 검증 → 최종 PR. 작은 작업은 triage-fix/task-run으로 충분; work가 "크다"고 판단했거나 사용자가 /milestone 로 명시 호출할 때만.
argument-hint: <큰 업무 설명 | 노션·슬랙 링크>
disable-model-invocation: true
---

# milestone — 큰 업무를 개발팀처럼 나눠 실행

큰 업무를 받아 **작은 태스크로 쪼개고, 관련끼리 그룹으로 묶어(그룹=개발자 1명), 그룹은 병렬·
그룹 내는 순차로** 실행해 최종 PR까지 올린다. 입력: `$ARGUMENTS`

**정신 모델 — 개발팀 협업.** 애매하면 "실제 개발팀이면?"으로 판단한다. 상세 설계는
`${CLAUDE_PLUGIN_ROOT}/.claude/docs/milestone-spec.md`(있으면)를 참고하되, 이 스킬 절차가 실행 기준이다.

> 전역 스킬. 프로젝트 고유값은 `<repo>/.claude/triage.config.json`(없으면 `/triage-init`)에서 읽는다.
> 특히 `{milestone}`(base_branch·max_issues·max_parallel), `{models}`, `{branch_prefix}`(milestone/group)를 쓴다.

## 핵심 원칙 (역할 분리)

- **컨트롤러(메인)는 판단하고 시킨다. 실행은 서브가 한다.**
  - 판단·상태파일 쓰기(plan.md 등)·서브에 넘길 값 조립 = 컨트롤러.
  - **git/gh 실행(브랜치·worktree·PR·머지·close·정리) = `git-writer`.** **테스트·full_verify 실행 = `qa`.**
    컨트롤러는 이런 **무겁고·부작용 있고·원문 뱉는 실행**을 직접 안 한다. 단 **상태 파일(plan.md·search-cache) 읽기·쓰기와
    가벼운 로컬 조회(SHA·브랜치명 확인)는 컨트롤러가 직접 한다** — 위임할 만큼 무겁지도 원문을 쌓지도 않으니까.
- **컨트롤러 컨텍스트에 원문(diff·로그·파일 전문)을 쌓지 않는다.** 에이전트 간 공유는 구조화 산출물로
  (result JSON·evidence packet·change-map·verify.log·search-cache).
- **막히거나 깨지면 새 이슈로 남기고 계속.** 추정으로 뚫고 가지 않는다. 성공한 태스크만 커밋된다.
- **각 태스크는 정식 loop.md 루프**(triage-fix/task-run의 5단계)를 재사용한다. base 브랜치로 그룹 브랜치를 주입하고, 마일스톤 모드라 태스크 루프는 PR·이슈 브랜치를 만들지 않는다.

## 상태 파일 (메인 레포 중앙 — 컨트롤러만 씀, 코드만 worktree)

`<repo>/.claude/loops/<마일스톤슬러그>/` (`.git/info/exclude`에 `.claude/loops/` 추가, 마일스톤 종료 후 삭제):
- `plan.md` — 마일스톤 전체 계획(살아있는 문서, 조정 시 갱신).
- `search-cache.json` — 탐색 결과 맵(`키워드/심볼 → [위치]` + `file→producing_sha` 메타). 컨트롤러가 직렬 병합.
- `groups/<그룹>/tasks/<이슈#N>/{loop.md, change-map.md, verify.log}` — 각 태스크 산출물(경로가 그룹·이슈별이라 race 없음).

그룹 워커는 **코드만 자기 worktree에서** 작업하고, 상태 산출물은 위 **메인 레포 절대경로**에 쓴다.

## 재진입 (컴팩션·세션 사망·태스크 추가)

마일스톤은 규모가 커서 한 세션이 컴팩션·종료를 맞을 수 있다. 상태가 전부 외부화돼 있으니 새 세션에서 이어간다.
**아래 순서로 현재 위치를 재구성**한다: ① `plan.md`(태스크·그룹·순서·모드·이슈#N) → ② `groups/<그룹>/tasks/<이슈#N>/`
산출물 유무 → ③ git·gh 상태(그룹 브랜치 커밋·그룹 PR·통합/막힘 이슈·마일스톤 HEAD).
**완료 판정은 추정 말고 사실로**: 태스크 완료 = 그룹 브랜치에 그 태스크 commit_sha 존재 / 그룹 완료 = 그룹 PR 머지됨 /
막힘 = 막힘 이슈(`[milestone:<슬러그>][task:<이슈#N>]`) 열림. **이미 커밋된 성공 태스크는 다시 돌리지 않고**, 미완료·막힘부터 이어서 실행한다.

**태스크 추가 재진입** — 진행 중 마일스톤에 새 수정사항이 들어오면(예: `/work` 0단계에서 라우팅):
① 위 재진입 순서로 현재 위치 재구성 → ② **planner 재계획** — 새 수정사항을 태스크로 분할, 기존 그룹 배치 또는
새 그룹(ownership matrix 겹침 재검사 — 겹치면 같은 그룹에서 순차), `plan.md` 갱신(기존 이슈 #N 보존) →
③ **재계획 승인 ✋** — 재계획 결과(신규 태스크·파일계획·그룹 배치·겹침 리포트)를 사용자에게 보여주고 승인 후 ④로
(§가드 "승인 전 이슈 생성 금지" 동일 적용. 실행 모드는 기존 ⑤에서 확정한 모드[중지/바이패스]를 승계하되,
이 승인은 ⑤와 같은 계획 승인 성격이라 바이패스여도 여기선 정지) →
④ **git-writer로 새 이슈 생성**·#N을 plan.md에 고정(§⑥ 관례) → ⑤ 해당 그룹에서 **정식 태스크 루프**(§⑧)로 실행,
이후 그룹 PR → 최종 PR 흐름에 합류(최종 PR이 이미 열려 있으면 갱신 — **갱신 전에도 ⑩의 부채 테스트 감사와
full_verify를 재확인**한다. 추가 태스크의 테스트가 감사 없이 최종 PR에 들어가지 않게).

## 마일스톤 적층 (미머지 마일스톤 위에 후속 마일스톤)

A(미머지 마일스톤)가 main 머지를 기다리는 동안 후속 마일스톤 C를 시작하거나, 다른 마일스톤 B를
C로 흡수할 때(예: `/work` 0단계 복수 감지 ⓒ) 적용한다. base 선택은 §⑤ 승인에서 함께 확정한다(정지점 추가 없음).
① **시작** — 진행 순서는 건너뛰지 않고 §①부터 정상 진행(⑤ 승인 경유). 적층에서 달라지는 건
  §⑦ 브랜치 생성 시 C의 base(`{milestone.base_branch}`)가 A 브랜치가 되는 것뿐이다.
② **B 흡수** — 살릴 태스크만 **체리픽**으로 선별(태스크당 1커밋이라 태스크 단위 선별 가능, 연속 구간은
  `git cherry-pick <시작>..<끝>` 범위로 한 번에. 머지+revert는 "넣었다 뺀" 흔적이 이력에 남아 쓰지 않는다).
  선별 내역(살릴/버릴 B 태스크)은 §⑤ 승인 자료에 포함한다.
  얹은 직후 **full_verify 1회** — A·B가 각자 green이어도 조합은 깨질 수 있고, 이 관문 없이는 깨진 베이스 위에 태스크가 쌓인다.
  체리픽된 B 태스크의 테스트도 **C ⑩ 부채 감사 범위에 포함**된다(B 쪽에서 감사받지 않았으므로).
③ **C 최종 PR base = A 브랜치**(main 아님) — main으로 열면 diff에 A 변경이 통째로 섞여 리뷰 불가.
  A가 main 머지·브랜치 삭제되면 GitHub이 C PR을 main으로 자동 retarget.
④ **A 전진 추적** — A가 전진하면 C에 주기적으로 머지-인(§⑨ 재검증 원칙과 동일). 건너뛰면 C가 stale 상태로 검증을 통과한다.
⑤ **수렴** — A → main 먼저, 그다음 C → main. 사실상 한 몸이면 C를 A에 머지해 main 관문을 A 최종 PR 하나로 수렴.
  ⚠️ **retarget 경고**: C 머지 전에 A **원격** 브랜치 삭제(또는 C base를 main으로 수동 변경)가 먼저다 —
  retarget은 base 브랜치 **삭제 시에만** 발동하므로, 그 전에 C를 머지하면 main이 아닌 A로 들어간다(실제 발생 사례).
⑥ **B 정리** — GitHub Milestone close(git-writer `op=close-milestone` — §⑩ 정리와 동일 절차, 열린 이슈 확인 ✋ 포함), 살아남은 태스크 이슈는 C에서 close 연결, 미완 태스크는 C `plan.md`에 재등록,
  B 브랜치·worktree·상태 폴더 정리. 체리픽은 SHA가 바뀌어 B 쪽 완료 추적("그룹 브랜치에 commit_sha 존재")이 끊기므로,
  이 장부 정리를 건너뛰면 완료 판정이 어긋난다.

## 진행 순서

### 0단계 — 설정 로드
triage-fix와 동일 + `{milestone}`·`{models}`·`{branch_prefix.milestone|group}` 확보. `{models}` 있으면 각 서브에이전트를 그 모델로 스폰.
**Serena 활성화도 triage-fix 0단계와 동일** — `serena=true`면 메인이 `mcp__serena__get_current_config`로 멱등 확인 후
필요 시 `mcp__serena__activate_project <레포 절대경로>` 1회(실패 시 한 줄 알리고 계속). 멱등 확인은 0단계 1회가 아니라
**탐색 단계 진입 시마다**(① 위임 직전, 순차 worktree 사용 후 복귀 시) 수행한다 — Serena 서버는
**세션당 1개·활성 프로젝트 1칸·서브 전원 공유**(§⑧ 워커 정책의 근거).

### ① 파악·분할 (issue-triage → planner)
- 위임 직전 **Serena 멱등 확인**(0단계 활성화 절차) — 탐색 단계 진입 시점. issue-triage·planner에
  `serena` 여부와 **레포 절대경로**를 전달하고, 보고 첫머리의 `serena 폴백(사유)` 표기는 사용자 보고에 전파한다.
- 입력(링크면 소스 읽기) 파악. **issue-triage로 evidence packet** 생산(관련 파일:줄·심볼·의심원인).
- **planner 위임**: evidence packet + config(`convention_doc`·`tech_stack`·`serena`) 전달. planner가 태스크 분할.

### ② 파일 계획 · ③ 그룹핑 (planner)
- planner가 각 태스크의 파일 계획 + **완료기준(테스트로)** 작성, 관련·의존 태스크를 **같은 그룹**으로 묶고,
  **ownership matrix**로 그룹 간 파일 겹침을 기계 검사(겹치면 합치기/경고). 공통부는 이득일 때만 별도 태스크로.
- planner 출력을 `plan.md`에 기록. 태스크 수가 `{milestone.max_issues}` 초과면 "여러 마일스톤으로 쪼갤까요/진행할까요" 확인.

### ④ 순서 (planner)
- 그룹 내 태스크 순서 결정(그룹 간은 독립).

### ⑤ 승인 ✋ (단일 정지점 — 계획 + 모드)
- 계획(태스크·파일계획·완료기준·그룹 + **겹침 리포트**)을 사용자에게 보여주고, 그 자리에서
  **실행 모드[중지/바이패스]**를 1회 확정한다(`AskUserQuestion`). 정지점을 두 번 만들지 않는다.
  - **중지**: 태스크마다 사람 승인 + 그룹 PR 사람 리뷰·머지. **항상 순차**(병렬 끔).
  - **바이패스**: 자동 진행, 그룹 PR green이면 자동 머지(이력 남김). 병렬(§⑧). **막힌 건 새 이슈로.**
- **진행 중 마일스톤이 감지되면 base 선택도 같은 질문에 합친다**: `{default_branch}`(독립) /
  진행 중 `<A>` 브랜치(적층 — §마일스톤 적층 적용). 적층이면 ⑦ 브랜치 base·⑩ 최종 PR base가 A 브랜치가 된다.
- 어느 모드든 **최종 main PR(⑩)은 항상 정지** — 사람이 머지.

### ⑥ 이슈 생성 (git-writer)
- **GitHub Milestone 생성**(git-writer `op=create-milestone` — 동명 있으면 재사용).
- 태스크별 **이슈 생성**(git-writer). **이슈 번호(#N)를 태스크 안정 키로 plan.md에 고정**(재계획해도 보존).

### ⑦ 브랜치 · worktree (git-writer)
- **마일스톤 브랜치** `{branch_prefix.milestone}<슬러그>`를 `{milestone.base_branch|default_branch}`에서 생성
  (적층이면 ⑤에서 고른 A 브랜치 — §마일스톤 적층).
- **그룹 브랜치** `{branch_prefix.group}<슬러그>-<그룹>`을 마일스톤 브랜치에서 생성.
- 바이패스+병렬이면 그룹마다 **worktree**(`op=add-worktree`). 중지 모드(순차)면 worktree 없이 순차 처리 가능 —
  이 경우 Serena activate 대상은 **메인 레포**다(0단계 활성화 그대로 — worktree 경로 전환 없음).
- **worktree 의존성 준비**: 새 worktree는 `node_modules` 등 의존성이 없어 테스트·빌드가 바로 안 돈다.
  worktree 생성 직후 **의존성 설치**(`{install_command}` 있으면, 예 `pnpm install`)를 실행한다. pnpm/yarn은 store
  공유로 대개 저렴. install 명령이 없거나 불필요한 스택이면 생략(config에 없으면 안 돌림).

### ⑧ 실행 (그룹=병렬, 그룹 내=순차)
- **병렬 폭 `{milestone.max_parallel}`**(중지 모드면 1=순차). 각 그룹은 자기 worktree에서 태스크를 **순차**로:
  - 각 태스크 = **정식 loop.md 루프**(triage-fix=버그/task-run=기능). 넘길 것: loop.md 경로, planner 계획,
    `base_branch=그룹 브랜치`, config(`test_command`·`serena`·`models`…). 마일스톤 모드라 태스크 루프는 **PR·이슈 브랜치 안 만듦**.
  - **Serena 워커 정책(모드별 — 워커 스폰 프롬프트에 명시)**: **병렬(바이패스)** = 워커 **Serena 호출 금지
    (grep/Glob/Read만)** — 활성 프로젝트 1칸을 병렬 워커가 경합하고, 실수 호출 시 메인 레포 기준 결과가 반환돼
    혼동된다(워커는 planner 계획+search-cache로 탐색 수요가 낮아 실손 적음). **순차(중지)** = worktree를 만든
    경우에 한해 워커가 **자기 worktree 절대경로로 activate 후 사용 허용**(동시 사용자 없음. 무worktree 순차는
    메인 레포 그대로 — §⑦) — 첫 질의 워밍업(수십 초/worktree) 비용 인지.
    병렬이면 워커에 넘기는 config의 `serena`도 **false로 내려** 전달한다(스폰 프롬프트 금지 지시와 이중 안전 —
    에이전트의 "serena=false면 serena 툴 사용 금지" 규칙과 기계적으로 맞물림). 순차는 `serena=true` 유지.
  - implementer 구현+완료기준 테스트 작성 → **커밋 후보 diff 기준 change-map** 생성 → 자가체크(code-reviewer+policy-checker+qa).
  - **자가체크 green이면 git-writer가 그룹 브랜치에 커밋**. 실패(막힘/max_iter/qa 불통과)면 **커밋 안 함 + 새 이슈**(중복 마커 `[milestone:<슬러그>][task:<이슈#N>]`, 생성 전 같은 키 확인) + 다음 태스크. 실패 태스크 원 이슈는 열어둠.
  - 중지 모드면 태스크마다 4단계 승인 정지.
  - **태스크 단계에선 부채 테스트 감사를 하지 않는다** — 추가된 테스트는 후속 태스크의 회귀 그물로 남기고, 감사는 ⑩에서 일괄.
- **탐색 캐시**: 서브가 탐색하면 cache_delta를 result JSON으로 반환 → 컨트롤러가 `search-cache.json`에 직렬 병합. 파일 변경(SHA) 시 그 파일 엔트리 무효화.
  - **hit 계측**: 서브는 result JSON에 `cache_hits`·`cache_misses`도 담는다. 컨트롤러가 누적해 `search-cache.json`의 `_stats`
    (`total_hits`·`total_misses`·`hit_rate`)에 기록하고, ⑩ 최종 PR 본문(또는 로그)에 **히트율**을 남긴다 — 캐시가 실제 이득인지 데이터로 남긴다.

### ⑨ 그룹 PR + 머지 전 검증 (qa 검증 · git-writer 실행)
그룹의 태스크가 다 끝나면:
- git-writer가 그룹 브랜치 → 마일스톤으로 **PR** 생성.
- **커밋 M 생성**: git-writer `op=prepare-merge`(임시 검증 worktree에서 [마일스톤 최신+그룹] 합침) → **M의 SHA 반환**.
  머지 충돌이면 여기서 failed → 아래 red 처리.
- **머지 전 검증(qa)**: 반환된 M(검증 worktree)에서 `{loop.full_verify_command}` 실행(merge queue식).
  이 qa는 **테스트 실행·판정만** 하므로(감사 아님) `{models.qa}` 대신 **하위 모델(예: `{models.git-writer}` 급)로 스폰 가능** — 토큰 절약.
  - **green** → (중지=사람 머지 승인 후 / 바이패스=즉시) git-writer `op=merge`로 **검증한 그 M을 그대로**
    마일스톤 HEAD로 ff-only 확정(재머지 아님) + 검증 worktree 정리. 이어 **머지 후 정리**: 성공 태스크 이슈만 `op=close-issue`, 그룹 브랜치·worktree `op=cleanup-branch`/`remove-worktree`.
  - **red/충돌** → 머지 안 함 + 검증 worktree 정리(`op=remove-worktree`) + **통합 이슈** 생성 + 그룹 PR 열어둠 + 최종 PR에 "미머지" 표시.
- 다른 그룹이 먼저 머지돼 마일스톤이 전진했으면 M을 다시 만들어(prepare-merge 재실행) 재검증(stale이면 반복).

### ⑩ 최종 PR ✋
- 모든 그룹이 머지되었거나 미머지로 확정 표기된 후, 최종 `full_verify`(qa) 1회.
- **부채 테스트 감사(최종 full_verify green 후 · 최종 PR 생성 전)** — 마일스톤 전체가 추가한 테스트만
  "깨지면 버그인가, 리팩토링인가" 기준으로 분류(기존 테스트 제안 금지), 부채 제거는 **정리 커밋**
  (마일스톤 브랜치, git-writer)으로 → `full_verify` 재확인(red면 제거 롤백·유지). 부채 0건이면 그대로 진행.
- git-writer가 마일스톤 브랜치 → main **PR 남기고 정지**
  (적층이면 base는 main이 아니라 A 브랜치 — §마일스톤 적층 ③. **적층 머지 주의**: C 머지 전 A **원격** 브랜치
  삭제 선행 — §마일스톤 적층 ⑤ retarget 경고). 미머지 그룹 있으면 draft.
- PR 본문: 완료 태스크 / 미완료·통합·미머지 목록 / 정리된 테스트 내역 / 실행 중 결정 요약.
- **어느 모드든 main 머지는 사람이 한다.** 최종 PR 머지 후(사용자 "머지했어/정리해줘" 발화 — task-run 7단계와 동일 시점,
  진입 조건도 7단계 1과 동일: **사실 확인** — fetch로 머지 커밋 실재 확인, 미머지면 중단) **머지 후 정리**:
  1. **태깅**(레포 관례가 있을 때) — 버전 bump 포함 마일스톤이면 머지 커밋에 태그·push(git-writer `op=tag` — 단일
     7단계 2와 동일). 적층 연속 머지(A→main 후 C→main)면 **머지된 순서대로** 태그를 단다(버전 역전 방지).
  2. **GitHub Milestone close**(git-writer `op=close-milestone`) — Milestone에 **열린 이슈**(미완 태스크·통합·막힘)가 남았으면
     닫기 전 확인 ✋: ⓐ 이슈 이관(마일스톤 해제 또는 다음 마일스톤) 후 close / ⓑ 열어둠. 열린 이슈 0건이면 바로 close.
     **자동 close 금지 — 조용히 묻히는 미완 작업 방지.**
  3. `.claude/loops/<슬러그>/` 삭제 — **2의 close가 완료된 경우에만.** ⓑ(열어둠)를 골랐으면 `plan.md`를 보존한다
     (`/work` 재감지·태스크 추가 재진입 가능 유지). 단일 스킬 7단계 sweep은 `plan.md` 있는 이 폴더를 건드리지
     않는다 — 정리는 여기가 담당.
  4. **브랜치 정리** — 마일스톤 브랜치·잔여 그룹 브랜치 `op=cleanup-branch`(머지된 것만 — 7단계 sweep 안전선 동일).

## 이벤트 발행 (선택 — §triage-fix와 동일 발행기)
work-* 이벤트에 파라미터 추가: `work_type=milestone`·`milestone=<슬러그>`·`scope=issue|milestone`·`group=<그룹>`.
태스크 종료는 `scope=issue`(그룹 PR 전이면 pr_url 생략), 최종 PR은 `scope=milestone`.

## 가드 (어기지 말 것)
- **⑤ 승인 전 이슈·브랜치·코드 생성 금지.** 계획까지만, 그다음 정지.
- **컨트롤러는 git/gh/테스트 직접 실행 금지** — git-writer/qa 위임. 원문 diff·로그를 컨텍스트에 쌓지 않는다.
  (상태 파일 읽기·쓰기와 가벼운 로컬 조회(SHA·브랜치명)는 예외 — 컨트롤러가 직접.)
- **막힘·통합 깨짐 = 새 이슈**(뚫고 가기 금지). 성공한 태스크만 커밋.
- **머지 전 검증(qa) green이어야 마일스톤에 머지.** 깨진 게 마일스톤 브랜치에 안 들어간다.
- **main 머지는 자동 금지** — 최종 PR에서 항상 사람 관문.
- **마일스톤별 폴더·브랜치 슬러그로 격리** — 여러 마일스톤 동시 실행 OK(전역 락 불필요).
